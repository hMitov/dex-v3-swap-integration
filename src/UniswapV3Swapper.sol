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

/**
 * @title UniswapV3Swapper
 * @notice A contract for executing swaps on Uniswap V3 with TWAP-based slippage protection
 * @dev Supports single-hop and multihop swaps with configurable slippage protection
 */
contract UniswapV3Swapper is IUniswapV3Swapper, ReentrancyGuard, Pausable, AccessControl {
    ISwapRouter public immutable router;
    IWETH public immutable wETH;
    ITWAPPriceProvider public twapProvider;

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    uint32 public twapPeriod = 0;
    uint256 public twapSlippageBps = 100; // 1.00% buffer;

    /**
     * @notice Constructor to initialize the swapper contract
     * @param _routerAddress The Uniswap V3 SwapRouter address
     * @param _wETHAddress The WETH contract address
     * @param _twapProvider The TWAP price provider contract address
     */
    constructor(address _routerAddress, address _wETHAddress, address _twapProvider) {
        require(_routerAddress != address(0), "Router address cannot be zero");
        require(_wETHAddress != address(0), "WETH address cannot be zero");
        require(_twapProvider != address(0), "TWAP provider address cannot be zero");

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

    /**
     * @notice Pause the contract (only pauser role)
     */
    function pause() external override onlyPauser {
        _pause();
    }

    /**
     * @notice Unpause the contract (only pauser role)
     */
    function unpause() external override onlyPauser {
        _unpause();
    }

    /**
     * @notice Grant pauser role to an account (only admin role)
     * @param _account The account to grant the pauser role to
     */
    function grantPauserRole(address _account) external override onlyAdmin {
        require(_account != address(0), "Zero address not allowed");
        grantRole(PAUSER_ROLE, _account);
    }

    /**
     * @notice Revoke pauser role from an account (only admin role)
     * @param _account The account to revoke the pauser role from
     */
    function revokePauserRole(address _account) external override onlyAdmin {
        require(_account != address(0), "Zero address not allowed");
        revokeRole(PAUSER_ROLE, _account);
    }

    /**
     * @notice Set the TWAP period for price calculations (only admin role)
     * @param _twapPeriod The TWAP period in seconds
     */
    function setTwapPeriod(uint32 _twapPeriod) external override onlyAdmin {
        require(_twapPeriod > 0, "TWAP period must be greater than 0");
        twapPeriod = _twapPeriod;
    }

    /**
     * @notice Set the TWAP slippage buffer in basis points (only admin role)
     * @param _twapSlippageBps The TWAP slippage buffer in basis points
     */
    function setTwapSlippageBps(uint256 _twapSlippageBps) external override onlyAdmin {
        require(_twapSlippageBps <= 10000, "TWAP slippage buffer must be less than or equal to 100%");
        twapSlippageBps = _twapSlippageBps;
    }

    /**
     * @notice Execute a single-hop exact input swap
     * @param tokenIn The input token address (use address(0) for ETH)
     * @param tokenOut The output token address (use address(0) for ETH)
     * @param amountIn The amount of input tokens to swap
     * @param poolFee The pool fee tier (500, 3000, or 10000)
     * @param deadline The deadline for the swap
     * @param amountOutMinimum The minimum amount of output tokens to receive
     * @return amountOut The amount of output tokens received
     */
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

        bool isNativeIn = (tokenIn == address(0));
        bool isNativeOut = (tokenOut == address(0));
        address actualTokenIn = _normalizeToken(tokenIn);
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

    /**
     * @notice Execute a single-hop exact output swap
     * @param tokenIn The input token address (use address(0) for ETH)
     * @param tokenOut The output token address (use address(0) for ETH)
     * @param amountOut The exact amount of output tokens to receive
     * @param amountInMaximum The maximum amount of input tokens to spend
     * @param poolFee The pool fee tier (500, 3000, or 10000)
     * @param deadline The deadline for the swap
     * @return amountIn The amount of input tokens actually spent
     */
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

        bool isNativeIn = (tokenIn == address(0));
        bool isNativeOut = (tokenOut == address(0));
        address actualTokenIn = _normalizeToken(tokenIn);
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

    /**
     * @notice Execute a multihop exact input swap
     * @param tokens Array of token addresses for the swap path (use address(0) for ETH/WETH)
     * @param poolFees Array of pool fees for each hop
     * @param amountIn The amount of input tokens to swap
     * @param amountOutMinimum The minimum amount of output tokens to receive
     * @param deadline The deadline for the swap
     * @return amountOut The amount of output tokens received
     */
    function swapExactInputMultihop(
        address[] calldata tokens,
        uint24[] calldata poolFees,
        uint256 amountIn,
        uint256 amountOutMinimum,
        uint256 deadline
    ) external payable override nonReentrant whenNotPaused returns (uint256 amountOut) {
        require(tokens.length >= 2, "At least 2 tokens required");
        require(poolFees.length == tokens.length - 1, "Pool fees length must match hops");
        require(amountIn > 0, "amountIn must be greater than zero");
        require(deadline >= block.timestamp, "Deadline passed");

        for (uint256 i = 0; i + 1 < tokens.length; i++) {
            require(
                twapProvider.isPairSupported(_normalizeToken(tokens[i]), _normalizeToken(tokens[i + 1]), poolFees[i]),
                "Token pair not allowed"
            );
        }

        if (amountOutMinimum == 0) {
            amountOutMinimum = _twapMinOutMultihop(tokens, poolFees, amountIn);
        }

        // Funds in, approve, and swap (scoped to free stack slots)
        {
            bool isNativeIn = (tokens[0] == address(0));
            address actualTokenIn = isNativeIn ? address(wETH) : tokens[0];

            _takeFunds(actualTokenIn, amountIn, isNativeIn);
            _approveToken(actualTokenIn, amountIn);

            bytes memory path = _buildPath(tokens, poolFees);

            ISwapRouter.ExactInputParams memory params = ISwapRouter.ExactInputParams({
                path: path,
                recipient: address(this),
                deadline: deadline,
                amountIn: amountIn,
                amountOutMinimum: amountOutMinimum
            });

            amountOut = router.exactInput(params);

            _approveToken(actualTokenIn, 0);
        }

        require(amountOut >= amountOutMinimum, "Slippage limit exceeded");

        // Payout (scoped to free stack slots)
        {
            bool isNativeOut = (tokens[tokens.length - 1] == address(0));
            address actualTokenOut = isNativeOut ? address(wETH) : tokens[tokens.length - 1];
            _sendFunds(actualTokenOut, msg.sender, amountOut, isNativeOut);
        }

        emit SwapExecuted(msg.sender, tokens[0], tokens[tokens.length - 1], amountIn, amountOut);
    }

    /**
     * @notice Execute a multihop exact output swap
     * @param tokens Array of token addresses for the swap path (use address(0) for ETH/WETH)
     * @param poolFees Array of pool fees for each hop
     * @param amountOut The exact amount of output tokens to receive
     * @param amountInMaximum The maximum amount of input tokens to spend
     * @param deadline The deadline for the swap
     * @return amountIn The amount of input tokens actually spent
     */
    function swapExactOutputMultihop(
        address[] calldata tokens,
        uint24[] calldata poolFees,
        uint256 amountOut,
        uint256 amountInMaximum,
        uint256 deadline
    ) external payable override nonReentrant whenNotPaused returns (uint256 amountIn) {
        require(tokens.length >= 2, "At least 2 tokens required");
        require(poolFees.length == tokens.length - 1, "Pool fees length must match hops");
        require(amountOut > 0, "amountOut must be greater than zero");
        require(deadline >= block.timestamp, "Deadline passed");

        // Per-hop whitelist (normalize inline to avoid extra locals)
        for (uint256 i = 0; i + 1 < tokens.length; i++) {
            require(
                twapProvider.isPairSupported(_normalizeToken(tokens[i]), _normalizeToken(tokens[i + 1]), poolFees[i]),
                "Token pair not allowed"
            );
        }

        // Auto-derive maxIn from chained TWAP if caller passed 0
        if (amountInMaximum == 0) {
            amountInMaximum = _twapMaxInMultihop(tokens, poolFees, amountOut);
        }
        require(amountInMaximum > 0, "amountInMaximum is zero");

        // Funds in, approve, and swap (scoped to free stack slots)
        {
            bool isNativeIn = (tokens[0] == address(0));
            address actualTokenIn = isNativeIn ? address(wETH) : tokens[0];

            _takeFunds(actualTokenIn, amountInMaximum, isNativeIn);
            _approveToken(actualTokenIn, amountInMaximum);

            bytes memory path = _buildReversedPath(tokens, poolFees);

            ISwapRouter.ExactOutputParams memory params = ISwapRouter.ExactOutputParams({
                path: path,
                recipient: address(this),
                deadline: deadline,
                amountOut: amountOut,
                amountInMaximum: amountInMaximum
            });

            amountIn = router.exactOutput(params);

            _approveToken(actualTokenIn, 0);

            // Refund leftover input (if any)
            if (amountIn < amountInMaximum) {
                _sendFunds(actualTokenIn, msg.sender, amountInMaximum - amountIn, isNativeIn);
            }
        }

        {
            bool isNativeOut = (tokens[tokens.length - 1] == address(0));
            address actualTokenOut = isNativeOut ? address(wETH) : tokens[tokens.length - 1];
            _sendFunds(actualTokenOut, msg.sender, amountOut, isNativeOut);
        }

        emit SwapExecuted(msg.sender, tokens[0], tokens[tokens.length - 1], amountIn, amountOut);
    }

    /**
     * @notice Build a swap path for exact input multihop swaps
     * @param tokens Array of token addresses for the swap path
     * @param poolFees Array of pool fees for each hop
     * @return path The encoded swap path
     */
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

    /**
     * @notice Build a reversed swap path for exact output multihop swaps
     * @param tokens Array of token addresses for the swap path
     * @param poolFees Array of pool fees for each hop
     * @return path The encoded reversed swap path
     */
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

    /**
     * @notice Calculate minimum output for exact input multihop swaps using TWAP
     * @param tokens Array of token addresses for the swap path
     * @param poolFees Array of pool fees for each hop
     * @param amountIn The amount of input tokens
     * @return The minimum output amount with slippage protection
     */
    function _twapMinOutMultihop(address[] calldata tokens, uint24[] calldata poolFees, uint256 amountIn)
        internal
        view
        returns (uint256)
    {
        require(tokens.length >= 2, "path too short");
        require(tokens.length == poolFees.length + 1, "fees mismatch");

        uint32 period = _resolveTwapPeriod();
        uint256 running = amountIn;

        for (uint256 i = 0; i < poolFees.length; i++) {
            require(running <= type(uint128).max, "amount too large");
            // No aIn / aOut / hopOut locals → fewer stack slots
            (running,) = twapProvider.getTwapPrice(
                _normalizeToken(tokens[i]), _normalizeToken(tokens[i + 1]), uint128(running), poolFees[i], period
            );
        }

        return (running * (10_000 - twapSlippageBps)) / 10_000;
    }

    /**
     * @notice Calculate maximum input for exact output multihop swaps using TWAP
     * @param tokens Array of token addresses for the swap path
     * @param poolFees Array of pool fees for each hop
     * @param amountOut The amount of output tokens desired
     * @return The maximum input amount with slippage protection
     */
    function _twapMaxInMultihop(address[] calldata tokens, uint24[] calldata poolFees, uint256 amountOut)
        internal
        view
        returns (uint256)
    {
        require(tokens.length >= 2, "path too short");
        require(tokens.length == poolFees.length + 1, "fees mismatch");

        uint32 period = _resolveTwapPeriod();
        uint256 running = amountOut;

        for (uint256 i = poolFees.length; i > 0;) {
            i--;
            require(running <= type(uint128).max, "amount too large");
            (running,) = twapProvider.getTwapPrice(
                _normalizeToken(tokens[i + 1]), _normalizeToken(tokens[i]), uint128(running), poolFees[i], period
            );
        }

        return (running * (10_000 + twapSlippageBps)) / 10_000;
    }

    /**
     * @notice Resolve the TWAP period to use for price calculations
     * @return p The TWAP period in seconds
     */
    function _resolveTwapPeriod() internal view returns (uint32 p) {
        p = twapPeriod == 0 ? twapProvider.defaultTwapPeriod() : twapPeriod;
    }

    /**
     * @notice Normalize token address (convert address(0) to WETH address)
     * @param token The token address to normalize
     * @return The normalized token address
     */
    function _normalizeToken(address token) internal view returns (address) {
        return token == address(0) ? address(wETH) : token;
    }

    /**
     * @notice Take funds from the user (ETH or ERC20 tokens)
     * @param actualToken The actual token address to transfer
     * @param amount The amount to transfer
     * @param isNative Whether the token is native ETH
     */
    function _takeFunds(address actualToken, uint256 amount, bool isNative) internal {
        if (isNative) {
            require(msg.value == amount, "ETH amount mismatch");
            wETH.deposit{value: amount}();
        } else {
            require(msg.value == 0, "ETH not expected");
            TransferHelper.safeTransferFrom(actualToken, msg.sender, address(this), amount);
        }
    }

    /**
     * @notice Send funds to the recipient (ETH or ERC20 tokens)
     * @param actualToken The actual token address to transfer
     * @param to The recipient address
     * @param amount The amount to transfer
     * @param toNative Whether to convert to native ETH
     */
    function _sendFunds(address actualToken, address to, uint256 amount, bool toNative) internal {
        if (toNative) {
            wETH.withdraw(amount);
            TransferHelper.safeTransferETH(to, amount);
        } else {
            TransferHelper.safeTransfer(actualToken, to, amount);
        }
    }

    /**
     * @notice Approve the router to spend tokens
     * @param token The token address to approve
     * @param amount The amount to approve
     */
    function _approveToken(address token, uint256 amount) internal {
        TransferHelper.safeApprove(token, address(router), amount);
    }

    /**
     * @notice Calculate minimum output for exact input single swaps using TWAP
     * @param tokenIn The input token address
     * @param tokenOut The output token address
     * @param amountIn The amount of input tokens
     * @param poolFee The pool fee tier
     * @return minOut The minimum output amount with slippage protection
     */
    function _twapMinOut(address tokenIn, address tokenOut, uint256 amountIn, uint24 poolFee)
        internal
        view
        returns (uint256 minOut)
    {
        require(amountIn <= type(uint128).max, "amountIn too large");
        (uint256 twapOut,) =
            twapProvider.getTwapPrice(tokenIn, tokenOut, uint128(amountIn), poolFee, _resolveTwapPeriod());
        minOut = (twapOut * (10_000 - twapSlippageBps)) / 10_000;
    }

    /**
     * @notice Calculate maximum input for exact output single swaps using TWAP
     * @param tokenIn The input token address
     * @param tokenOut The output token address
     * @param amountOut The amount of output tokens desired
     * @param poolFee The pool fee tier
     * @return maxIn The maximum input amount with slippage protection
     */
    function _twapMaxIn(address tokenIn, address tokenOut, uint256 amountOut, uint24 poolFee)
        internal
        view
        returns (uint256 maxIn)
    {
        require(amountOut <= type(uint128).max, "amountOut too large");
        (uint256 twapIn,) =
            twapProvider.getTwapPrice(tokenOut, tokenIn, uint128(amountOut), poolFee, _resolveTwapPeriod());
        maxIn = (twapIn * (10_000 + twapSlippageBps)) / 10_000;
    }

    // Function to receive ETH when WETH is withdrawn
    receive() external payable {}
}
