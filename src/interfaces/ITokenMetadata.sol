// SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;

/// @title ERC20 Token Metadata Interface
/// @notice Provides read-only access to token metadata
interface ITokenMetadata {
    /// @notice Returns the number of decimals used by the token
    function decimals() external view returns (uint8);

    /// @notice Returns the token symbol
    function symbol() external view returns (string memory);
}
