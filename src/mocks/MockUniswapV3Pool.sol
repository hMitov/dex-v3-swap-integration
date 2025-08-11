// SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;

import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

/// @title Mock Uniswap V3 Pool
/// @notice Simulates a Uniswap V3 pool for testing TWAP and swap-related logic
/// @dev Provides minimal state variables and a simplified `observe` implementation
contract MockUniswapV3Pool {
    /// @notice Address of token0 in the pool
    address public token0;
    /// @notice Address of token1 in the pool
    address public token1;
    /// @notice Pool fee in hundredths of a bip (e.g., 500 = 0.05%)
    uint24 public fee;
    /// @notice Liquidity value for compatibility (unused in mock logic)
    uint128 public liquidity;

    /// @notice Deploy a mock pool with token addresses and fee tier
    /// @param _token0 Address of token0
    /// @param _token1 Address of token1
    /// @param _fee Fee tier for the pool
    constructor(address _token0, address _token1, uint24 _fee) {
        token0 = _token0;
        token1 = _token1;
        fee = _fee;
    }

    /// @notice Simulate the Uniswap V3 `observe` function
    /// @dev Always returns a fixed tick cumulative and seconds per liquidity values
    /// @param secondsAgos Two-element array: [past seconds, 0]
    /// @return tickCumulatives Simulated cumulative ticks
    /// @return secondsPerLiquidityCumulativeX128s Simulated cumulative seconds per liquidity
    function observe(uint32[] calldata secondsAgos)
        external
        pure
        returns (int56[] memory tickCumulatives, uint160[] memory secondsPerLiquidityCumulativeX128s)
    {
        require(secondsAgos.length == 2, "Invalid secondsAgos length");

        tickCumulatives = new int56[](2);
        secondsPerLiquidityCumulativeX128s = new uint160[](2);

        // Current time (secondsAgo[1] = 0)
        tickCumulatives[1] = 0;
        secondsPerLiquidityCumulativeX128s[1] = 0;

        // Simulate a price ratio ~1:1 for secondsAgo[0]
        // -276325 is an arbitrary fixed tick for test purposes
        tickCumulatives[0] = -276325 * int56(secondsAgos[0]);
        secondsPerLiquidityCumulativeX128s[0] = uint160(secondsAgos[0]) * 1e18;
    }
}
