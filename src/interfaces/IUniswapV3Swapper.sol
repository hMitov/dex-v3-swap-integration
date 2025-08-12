// SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;

/// @title Interface for Uniswap V3 Swapper
/// @notice Defines swapping functions and admin controls for token pairs
interface IUniswapV3Swapper {
    /// @notice Emitted when a token pair is allowed for swapping
    event TokenPairAllowed(address indexed tokenIn, address indexed tokenOut);

    /// @notice Emitted when a token pair is revoked from swapping
    event TokenPairRevoked(address indexed tokenIn, address indexed tokenOut);

    /// @notice Emitted when a swap is executed
    event SwapExecuted(address indexed sender, address tokenIn, address tokenOut, uint256 amountIn, uint256 amountOut);

    /// @notice Grants the pauser role to an account
    function grantPauserRole(address account) external;

    /// @notice Revokes the pauser role from an account
    function revokePauserRole(address account) external;

    /// @notice Pauses all swap operations
    function pause() external;

    /// @notice Unpauses swap operations
    function unpause() external;

    /// @notice Sets the TWAP period
    function setTwapPeriod(uint32 twapPeriod) external;

    /// @notice Swaps an exact amount of input token for a minimum amount of output token in a single pool
    /// @return amountOut The amount of output token received
    function swapExactInputSingle(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint24 poolFee,
        uint256 deadline,
        uint256 amountOutMinimum
    ) external payable returns (uint256 amountOut);

    /// @notice Swaps a minimum amount of output token for up to a maximum amount of input token in a single pool
    /// @return amountIn The actual amount of input token spent
    function swapExactOutputSingle(
        address tokenIn,
        address tokenOut,
        uint256 amountOut,
        uint256 amountInMaximum,
        uint24 poolFee,
        uint256 deadline
    ) external payable returns (uint256 amountIn);

    /// @notice Swaps an exact amount of input token for a minimum amount of output token through multiple pools
    /// @return amountOut The amount of output token received
    function swapExactInputMultihop(
        address[] calldata tokens,
        uint24[] calldata poolFees,
        uint256 amountIn,
        uint256 amountOutMinimum,
        uint256 deadline
    ) external payable returns (uint256 amountOut);

    /// @notice Swaps a minimum amount of output token for up to a maximum amount of input token through multiple pools
    /// @return amountIn The actual amount of input token spent
    function swapExactOutputMultihop(
        address[] calldata tokens,
        uint24[] calldata poolFees,
        uint256 amountOut,
        uint256 amountInMaximum,
        uint256 deadline
    ) external payable returns (uint256 amountIn);
}
