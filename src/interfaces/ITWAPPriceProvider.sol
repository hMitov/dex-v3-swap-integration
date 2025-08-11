// SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;

/// @title TWAP Price Provider Interface
/// @notice Interface for querying Uniswap V3 TWAP prices and managing allowed pools
interface ITWAPPriceProvider {
    /// @dev Struct with pool metadata
    struct TokenPair {
        address token0; // lower-address token
        address token1; // higher-address token
        address pool; // Uniswap V3 pool
        uint24 fee; // fee tier
        bool isActive; // active status
    }

    /// @notice Emitted when a pair is registered
    event PairAdded(bytes32 indexed pairId, address token0, address token1, address pool, uint24 fee);
    /// @notice Emitted when a pair is removed
    event PairRemoved(bytes32 indexed pairId);

    function grantPauserRole(address account) external;
    function revokePauserRole(address account) external;
    function pause() external;
    function unpause() external;
    function addTokenPair(address _token0, address _token1, address _pool, uint24 _fee) external;
    function removeTokenPair(address _token0, address _token1, uint24 _fee) external;

    /// @notice Get TWAP quote for `_amountIn` of `_tokenIn` to `_tokenOut`
    /// @param _twapPeriod Pass 0 to use default
    function getTwapPrice(address _tokenIn, address _tokenOut, uint128 _amountIn, uint24 _fee, uint32 _twapPeriod)
        external
        view
        returns (uint256 amountOut, uint8 decimalsOut);

    /// @notice Check if pair is active
    function isPairSupported(address _tokenA, address _tokenB, uint24 _fee) external view returns (bool);

    /// @notice Default TWAP period used when `_twapPeriod` = 0
    function defaultTwapPeriod() external view returns (uint32);
}
