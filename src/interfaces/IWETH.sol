// SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title Wrapped Ether Interface
/// @notice Extends ERC20 with deposit and withdraw for native ETH
interface IWETH is IERC20 {
    /// @notice Deposit ETH and receive WETH
    function deposit() external payable;

    /// @notice Withdraw ETH by burning WETH
    /// @param amount The amount of WETH to unwrap
    function withdraw(uint256 amount) external;
}
