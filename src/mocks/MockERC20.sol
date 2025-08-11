// SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title Mock ERC20 Token
/// @notice Simple ERC20 token for testing purposes
/// @dev Mints an initial supply to the deployer and allows arbitrary minting
contract MockERC20 is ERC20 {
    /// @notice Deploy the mock token and mint initial supply
    /// @param name Token name
    /// @param symbol Token symbol
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {
        _mint(msg.sender, 1_000_000 * 10 ** decimals());
    }

    /// @notice Mint new tokens to an address
    /// @param to Address to receive minted tokens
    /// @param amount Number of tokens to mint
    /// @dev Accessible by anyone for testing flexibility
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}
