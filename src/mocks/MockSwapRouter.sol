// SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;
pragma abicoder v2;

import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./MockERC20.sol";
import "./MockWETH.sol";

/// @title Mock Uniswap V3 Swap Router
/// @notice Simulates Uniswap V3 swap functions for testing purposes
/// @dev Mints mock tokens instead of performing real swaps
contract MockSwapRouter is ISwapRouter {
    /// @notice Mocked output amount returned by swap functions
    uint256 public mockAmountOut = 1000;
    /// @notice Mocked input amount returned by exact output functions
    uint256 public mockAmountIn = 1000;
    /// @notice Token to mint and send in multihop swaps
    address public finalToken;

    /// @notice Set the mocked amountOut for swap simulations
    /// @param _amountOut The fake amountOut value to return
    function setAmountOut(uint256 _amountOut) external {
        mockAmountOut = _amountOut;
    }

    /// @notice Set the mocked amountIn for exact output swap simulations
    /// @param _amountIn The fake amountIn value to return
    function setAmountIn(uint256 _amountIn) external {
        mockAmountIn = _amountIn;
    }

    /// @notice Set the final token address used for multihop swaps
    /// @param _finalToken Address of token to mint and transfer in multihop
    function setFinalToken(address _finalToken) external {
        finalToken = _finalToken;
    }

    /// @notice Mocked exact input single swap function
    /// @param params The parameters for the swap
    /// @return amountOut The amount of output tokens received
    function exactInputSingle(ISwapRouter.ExactInputSingleParams calldata params)
        external
        payable
        override
        returns (uint256 amountOut)
    {
        MockERC20(params.tokenOut).mint(address(this), mockAmountOut);
        IERC20(params.tokenOut).transfer(params.recipient, mockAmountOut);
        return mockAmountOut;
    }

    /// @notice Mocked exact input swap function
    /// @param params The parameters for the swap
    /// @return amountOut The amount of output tokens received
    function exactInput(ISwapRouter.ExactInputParams calldata params)
        external
        payable
        override
        returns (uint256 amountOut)
    {
        address tokenToMint = finalToken;
        MockERC20(tokenToMint).mint(address(this), mockAmountOut);
        IERC20(tokenToMint).transfer(params.recipient, mockAmountOut);
        return mockAmountOut;
    }

    /// @notice Mocked exact output single swap function
    /// @param params The parameters for the swap
    /// @return amountIn The amount of input tokens spent
    function exactOutputSingle(ISwapRouter.ExactOutputSingleParams calldata params)
        external
        payable
        override
        returns (uint256 amountIn)
    {
        MockERC20(params.tokenOut).mint(address(this), params.amountOut);
        IERC20(params.tokenOut).transfer(params.recipient, params.amountOut);
        return mockAmountIn;
    }

    /// @notice Mocked exact output swap function
    /// @param params The parameters for the swap
    /// @return amountIn The amount of input tokens spent
    function exactOutput(ISwapRouter.ExactOutputParams calldata params)
        external
        payable
        override
        returns (uint256 amountIn)
    {
        address tokenToMint = finalToken;
        MockERC20(tokenToMint).mint(address(this), params.amountOut);
        IERC20(tokenToMint).transfer(params.recipient, params.amountOut);
        return mockAmountIn;
    }

    function uniswapV3SwapCallback(int256, int256, bytes calldata) external override {}
}
