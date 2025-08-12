// SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;
pragma abicoder v2;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol";
import "@uniswap/v3-core/contracts/interfaces/callback/IUniswapV3SwapCallback.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "./interfaces/IUniswapV3Swapper.sol";
import "./interfaces/IWETH.sol";
import "./interfaces/ITWAPPriceProvider.sol";

contract UniswapV3Swapper is IUniswapV3Swapper, ReentrancyGuard, Pausable, AccessControl {
    ISwapRouter public immutable router;
    IWETH public immutable wETH;
    ITWAPPriceProvider public twapProvider;

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    uint32 public twapPeriod = 0; // 0 => use twapProvider.defaultTwapPeriod()
    uint256 public twapSlippageBps = 50; // 0.50% buffer; apply -bps for minOut, +bps for maxIn

    constructor(address _routerAddress, address _wETHAddress, address _twapProvider) {
        router = ISwapRouter(_routerAddress);
        wETH = IWETH(_wETHAddress);
        twapProvider = ITWAPPriceProvider(_twapProvider);

        address deployer = msg.sender;
        _setupRole(DEFAULT_ADMIN_ROLE, deployer);
        _setupRole(ADMIN_ROLE, deployer);
        _setupRole(PAUSER_ROLE, deployer);

        _setRoleAdmin(PAUSER_ROLE, ADMIN_ROLE);
    }

    modifier onlyAdmin() {
        require(hasRole(ADMIN_ROLE, msg.sender), "Caller is not admin");
        _;
    }

    modifier onlyPauser() {
        require(hasRole(PAUSER_ROLE, msg.sender), "Caller is not pauser");
        _;
    }

    function pause() external override onlyPauser {
        _pause();
    }

    function unpause() external override onlyPauser {
        _unpause();
    }

    function grantPauserRole(address _account) external override onlyAdmin {
        require(_account != address(0), "Zero address not allowed");
        grantRole(PAUSER_ROLE, _account);
    }

    function revokePauserRole(address _account) external override onlyAdmin {
        require(_account != address(0), "Zero address not allowed");
        revokeRole(PAUSER_ROLE, _account);
    }

    // Resolve TWAP period (override or provider default)
    function _resolveTwapPeriod() internal view returns (uint32 p) {
        p = twapPeriod == 0 ? twapProvider.defaultTwapPeriod() : twapPeriod;
    }

    // Normalize token: map address(0) to WETH
    function _normalizeToken(address token) internal view returns (address) {
        return token == address(0) ? address(wETH) : token;
    }

    // Pull funds from user; if isNative==true we expect ETH and wrap to WETH
    function _takeFunds(address actualToken, uint256 amount, bool isNative) internal {
        if (isNative) {
            require(msg.value == amount, "ETH amount mismatch");
            wETH.deposit{value: amount}();
        } else {
            require(msg.value == 0, "ETH not expected");
            TransferHelper.safeTransferFrom(actualToken, msg.sender, address(this), amount);
        }
    }

    // Send funds to user; if toNative==true we unwrap WETH to ETH
    function _sendFunds(address actualToken, address to, uint256 amount, bool toNative) internal {
        if (toNative) {
            wETH.withdraw(amount);
            TransferHelper.safeTransferETH(to, amount);
        } else {
            TransferHelper.safeTransfer(actualToken, to, amount);
        }
    }

    // Approve router to spend `amount` of `token`
    function _approveToken(address token, uint256 amount) internal {
        TransferHelper.safeApprove(token, address(router), amount);
    }

    // TWAP helpers
    function _twapMinOut(address tokenIn, address tokenOut, uint256 amountIn, uint24 poolFee)
        internal
        view
        returns (uint256 minOut)
    {
        require(amountIn <= type(uint128).max, "amountIn too large");
        (uint256 twapOut, ) = twapProvider.getTwapPrice(
            tokenIn,
            tokenOut,
            uint128(amountIn),
            poolFee,
            _resolveTwapPeriod()
        );
        minOut = (twapOut * (10_000 - twapSlippageBps)) / 10_000;
    }

    function _twapMaxIn(address tokenIn, address tokenOut, uint256 amountOut, uint24 poolFee)
        internal
        view
        returns (uint256 maxIn)
    {
        require(amountOut <= type(uint128).max, "amountOut too large");
        (uint256 twapIn, ) = twapProvider.getTwapPrice(
            /* _tokenIn  */ tokenOut,
            /* _tokenOut */ tokenIn,
            uint128(amountOut),
            poolFee,
            _resolveTwapPeriod()
        );
        maxIn = (twapIn * (10_000 + twapSlippageBps)) / 10_000;
    }

    /* --------------------------- Single-hop swaps --------------------------- */

    function swapExactInputSingle(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint24 poolFee,
        uint256 deadline,
        uint256 amountOutMinimum
    ) external payable override nonReentrant whenNotPaused returns (uint256 amountOut) {
        require(tokenIn != tokenOut, "tokenIn and tokenOut must differ");
        require(amountIn > 0, "amountIn must be greater than zero");
        require(poolFee == 500 || poolFee == 3000 || poolFee == 10000, "Invalid pool fee");
        require(deadline >= block.timestamp, "Deadline passed");

        bool isNativeIn  = (tokenIn  == address(0));
        bool isNativeOut = (tokenOut == address(0));
        address actualTokenIn  = _normalizeToken(tokenIn);
        address actualTokenOut = _normalizeToken(tokenOut);

        require(twapProvider.isPairSupported(actualTokenIn, actualTokenOut, poolFee), "Token pair not allowed");

        if (amountOutMinimum == 0) {
            amountOutMinimum = _twapMinOut(actualTokenIn, actualTokenOut, amountIn, poolFee);
        }

        _takeFunds(actualTokenIn, amountIn, isNativeIn);
        _approveToken(actualTokenIn, amountIn);

        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: actualTokenIn,
            tokenOut: actualTokenOut,
            fee: poolFee,
            recipient: address(this),
            deadline: deadline,
            amountIn: amountIn,
            amountOutMinimum: amountOutMinimum,
            sqrtPriceLimitX96: 0
        });

        amountOut = router.exactInputSingle(params);

        _approveToken(actualTokenIn, 0);
        require(amountOut >= amountOutMinimum, "Slippage limit exceeded");

        _sendFunds(actualTokenOut, msg.sender, amountOut, isNativeOut);

        emit SwapExecuted(msg.sender, tokenIn, tokenOut, amountIn, amountOut);
    }

    function swapExactOutputSingle(
        address tokenIn,
        address tokenOut,
        uint256 amountOut,
        uint256 amountInMaximum,
        uint24 poolFee,
        uint256 deadline
    ) external payable override nonReentrant whenNotPaused returns (uint256 amountIn) {
        require(tokenIn != tokenOut, "tokenIn and tokenOut must differ");
        require(deadline >= block.timestamp, "Deadline passed");
        require(amountOut > 0, "amountOut must be greater than zero");
        require(poolFee == 500 || poolFee == 3000 || poolFee == 10000, "Invalid pool fee");

        bool isNativeIn  = (tokenIn  == address(0));
        bool isNativeOut = (tokenOut == address(0));
        address actualTokenIn  = _normalizeToken(tokenIn);
        address actualTokenOut = _normalizeToken(tokenOut);

        require(twapProvider.isPairSupported(actualTokenIn, actualTokenOut, poolFee), "Token pair not allowed");

        if (amountInMaximum == 0) {
            amountInMaximum = _twapMaxIn(actualTokenIn, actualTokenOut, amountOut, poolFee);
        }
        require(amountInMaximum > 0, "amountInMaximum is zero");

        _takeFunds(actualTokenIn, amountInMaximum, isNativeIn);
        _approveToken(actualTokenIn, amountInMaximum);

        ISwapRouter.ExactOutputSingleParams memory params = ISwapRouter.ExactOutputSingleParams({
            tokenIn: actualTokenIn,
            tokenOut: actualTokenOut,
            fee: poolFee,
            recipient: address(this),
            deadline: deadline,
            amountOut: amountOut,
            amountInMaximum: amountInMaximum,
            sqrtPriceLimitX96: 0
        });

        amountIn = router.exactOutputSingle(params);

        _approveToken(actualTokenIn, 0);

        // Refund leftover input
        if (amountIn < amountInMaximum) {
            _sendFunds(actualTokenIn, msg.sender, amountInMaximum - amountIn, isNativeIn);
        }

        // Deliver exact output
        _sendFunds(actualTokenOut, msg.sender, amountOut, isNativeOut);

        emit SwapExecuted(msg.sender, tokenIn, tokenOut, amountIn, amountOut);
    }

    // function swapExactInputMultihop(
    //     address[] calldata tokens,
    //     uint24[] calldata poolFees,
    //     uint256 amountIn,
    //     uint256 amountOutMinimum,
    //     uint256 deadline
    // ) external payable override nonReentrant whenNotPaused returns (uint256 amountOut) {
    //     uint256 tokenCount = tokens.length;
    //     require(tokenCount >= 2, "At least 2 tokens required");
    //     require(poolFees.length == tokenCount - 1, "Pool fees length must match hops");
    //     require(amountIn > 0, "amountIn must be greater than zero");
    //     require(deadline >= block.timestamp, "Deadline passed");

    //     // Validate allowed pairs
    //     for (uint256 i = 0; i < tokens.length - 1; i++) {
    //         // require(allowedPairs[tokens[i]][tokens[i + 1]], "Token pair not allowed");
    //         require(twapProvider.isPairSupported(tokens[i], tokens[i + 1], poolFees[i]), "Token pair not allowed");
    //     }

    //     if (tokens[0] == address(0)) {
    //         require(msg.value == amountIn, "ETH amount mismatch");
    //         wETH.deposit{value: amountIn}();
    //     } else {
    //         require(msg.value == 0, "ETH not expected");
    //         TransferHelper.safeTransferFrom(actualTokenIn, msg.sender, address(this), amountIn);
    //     }

    //     TransferHelper.safeApprove(actualTokenIn, address(router), amountIn);

    //     bytes memory path = _buildPath(tokens, poolFees);

    //     ISwapRouter.ExactInputParams memory params = ISwapRouter.ExactInputParams({
    //         path: path,
    //         recipient: address(this),
    //         deadline: deadline,
    //         amountIn: amountIn,
    //         amountOutMinimum: amountOutMinimum
    //     });

    //     amountOut = router.exactInput(params);

    //     TransferHelper.safeApprove(actualTokenIn, address(router), 0);

    //     require(amountOut >= amountOutMinimum, "Slippage limit exceeded");

    //     if (tokens[tokenCount - 1] == address(0)) {
    //         wETH.withdraw(amountOut);
    //         TransferHelper.safeTransferETH(msg.sender, amountOut);
    //     } else {
    //         TransferHelper.safeTransfer(actualTokenOut, msg.sender, amountOut);
    //     }

    //     emit SwapExecuted(msg.sender, tokens[0], tokens[tokenCount - 1], amountIn, amountOut);
    // }

    // function swapExactOutputMultihop(
    //     address[] calldata tokens,
    //     uint24[] calldata poolFees,
    //     uint256 amountOut,
    //     uint256 amountInMaximum,
    //     uint256 deadline
    // ) external payable override nonReentrant whenNotPaused returns (uint256 amountIn) {
    //     uint256 tokenCount = tokens.length;
    //     require(tokenCount >= 2, "At least 2 tokens required");
    //     require(poolFees.length == tokenCount - 1, "Pool fees length must match hops");
    //     require(amountOut > 0 && amountInMaximum > 0, "Invalid amounts");
    //     require(deadline >= block.timestamp, "Deadline passed");

    //     address actualTokenIn = tokens[0] == address(0) ? address(wETH) : tokens[0];
    //     address actualTokenOut = tokens[tokenCount - 1] == address(0) ? address(wETH) : tokens[tokenCount - 1];

    //     // Validate allowed pairs (unidirectional)
    //     for (uint256 i = 0; i < tokenCount - 1; i++) {
    //         require(twapProvider.isPairSupported(tokens[i], tokens[i + 1], poolFees[i]), "Token pair not allowed");
    //     }

    //     if (tokens[0] == address(0)) {
    //         require(msg.value >= amountInMaximum, "Insufficient ETH sent");
    //         wETH.deposit{value: amountInMaximum}();
    //     } else {
    //         require(msg.value == 0, "ETH not expected");
    //         // For exact output, we need to transfer tokens to the contract first
    //         // so they're available when the router calls back
    //         TransferHelper.safeTransferFrom(actualTokenIn, msg.sender, address(this), amountInMaximum);
    //     }

    //     // Approve router to spend tokens (for exact output, this is needed for the callback)
    //     TransferHelper.safeApprove(actualTokenIn, address(router), amountInMaximum);

    //     bytes memory path = _buildReversedPath(tokens, poolFees);

    //     // For exact output multihop, we need to handle the callback properly
    //     // The router will call back to us during the swap process
    //     ISwapRouter.ExactOutputParams memory params = ISwapRouter.ExactOutputParams({
    //         path: path,
    //         recipient: address(this),
    //         deadline: deadline,
    //         amountOut: amountOut,
    //         amountInMaximum: amountInMaximum
    //     });

    //     amountIn = router.exactOutput(params);

    //     TransferHelper.safeApprove(actualTokenIn, address(router), 0);

    //     // Refund leftover input tokens if any
    //     if (amountIn < amountInMaximum) {
    //         uint256 refund = amountInMaximum - amountIn;
    //         TransferHelper.safeApprove(actualTokenIn, address(router), 0);
    //         if (tokens[0] == address(0)) {
    //             wETH.withdraw(refund);
    //             TransferHelper.safeTransferETH(msg.sender, refund);
    //         } else {
    //             TransferHelper.safeTransfer(actualTokenIn, msg.sender, refund);
    //         }
    //     }

    //     // Handle output token
    //     if (tokens[tokenCount - 1] == address(0)) {
    //         wETH.withdraw(amountOut);
    //         TransferHelper.safeTransferETH(msg.sender, amountOut);
    //     } else {
    //         TransferHelper.safeTransfer(actualTokenOut, msg.sender, amountOut);
    //     }

    //     emit SwapExecuted(msg.sender, tokens[0], tokens[tokenCount - 1], amountIn, amountOut);
    // }

    function _buildPath(address[] calldata tokens, uint24[] calldata poolFees)
        internal
        view
        returns (bytes memory path)
    {
        require(tokens.length == poolFees.length + 1, "Invalid path length");

        bytes memory tempPath = abi.encodePacked(tokens[0] == address(0) ? address(wETH) : tokens[0]);

        for (uint256 i = 0; i < poolFees.length; i++) {
            tempPath =
                abi.encodePacked(tempPath, poolFees[i], tokens[i + 1] == address(0) ? address(wETH) : tokens[i + 1]);
        }

        path = tempPath;
    }

    function _buildReversedPath(address[] calldata tokens, uint24[] calldata poolFees)
        internal
        view
        returns (bytes memory path)
    {
        require(tokens.length == poolFees.length + 1, "Invalid path length");

        bytes memory tempPath =
            abi.encodePacked(tokens[tokens.length - 1] == address(0) ? address(wETH) : tokens[tokens.length - 1]);

        for (uint256 i = poolFees.length; i > 0;) {
            i--;
            address token = tokens[i] == address(0) ? address(wETH) : tokens[i];
            tempPath = abi.encodePacked(tempPath, poolFees[i], token);
        }

        path = tempPath;
    }

    // Function to receive ETH when WETH is withdrawn
    receive() external payable {}
}
