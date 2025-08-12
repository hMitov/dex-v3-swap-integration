// SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;

import "forge-std/Test.sol";
import "../../src/interfaces/ITWAPPriceProvider.sol";

contract MockTWAPProvider is ITWAPPriceProvider {
    mapping(bytes32 => bool) public supportedPairs;

    /// @notice Check if a token pair is supported by the mock TWAP provider
    /// @param tokenA The address of the first token in the pair
    /// @param tokenB The address of the second token in the pair
    /// @param fee The pool fee for the pair
    /// @return True if the pair is supported, false otherwise
    function isPairSupported(address tokenA, address tokenB, uint24 fee) external view override returns (bool) {
        bytes32 pairId =
            keccak256(abi.encodePacked(tokenA < tokenB ? tokenA : tokenB, tokenA < tokenB ? tokenB : tokenA, fee));
        return supportedPairs[pairId];
    }

    /// @notice Add a token pair to the mock TWAP provider
    /// @param tokenA The address of the first token in the pair
    /// @param tokenB The address of the second token in the pair
    /// @param fee The pool fee for the pair
    function addTokenPair(address tokenA, address tokenB, address, uint24 fee) external override {
        bytes32 pairId =
            keccak256(abi.encodePacked(tokenA < tokenB ? tokenA : tokenB, tokenA < tokenB ? tokenB : tokenA, fee));
        supportedPairs[pairId] = true;
    }

    function removeTokenPair(address, address, uint24) external override {}

    /// @notice Get the TWAP price for a token pair
    function getTwapPrice(address, address, uint128, uint24, uint32) external pure override returns (uint256, uint8) {
        return (1000, 18);
    }

    /// @notice Get the default TWAP period
    function defaultTwapPeriod() external pure override returns (uint32) {
        return 900;
    }

    /// @notice Pause the mock TWAP provider
    /// @dev This function does nothing in the mock implementation
    function pause() external override {}   

    /// @notice Unpause the mock TWAP provider
    /// @dev This function does nothing in the mock implementation
    function unpause() external override {}

    /// @notice Grant pauser role to an account
    /// @dev This function does nothing in the mock implementation
    function grantPauserRole(address) external override {}

    /// @notice Revoke pauser role from an account
    /// @dev This function does nothing in the mock implementation
    function revokePauserRole(address) external override {}
}
