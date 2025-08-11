// SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;

/// @title Mock Wrapped Ether (WETH)
/// @notice Minimal mock WETH token for testing purposes only
/// @dev Not production-ready — lacks events, safety checks, and ETH transfers
contract MockWETH {
    /// @notice Mapping from account to balance
    mapping(address => uint256) public balanceOf;

    /// @notice Mapping from account to spender allowances
    mapping(address => mapping(address => uint256)) public allowance;

    /// @notice Wrap ETH into mock WETH
    /// @dev Increases sender's WETH balance by the deposited ETH amount
    function deposit() external payable {
        balanceOf[msg.sender] += msg.value;
    }

    /// @notice Unwrap mock WETH into ETH (no ETH actually sent in mock)
    /// @param amount Amount of WETH to unwrap
    /// @dev In a real WETH, this would transfer ETH back to the caller
    function withdraw(uint256 amount) external {
        require(balanceOf[msg.sender] >= amount, "Insufficient balance");
        balanceOf[msg.sender] -= amount;
    }

    /// @notice Transfer WETH tokens to another address
    /// @param to Recipient address
    /// @param amount Amount of tokens to transfer
    /// @return success True if the transfer succeeded
    function transfer(address to, uint256 amount) external returns (bool success) {
        require(balanceOf[msg.sender] >= amount, "Insufficient balance");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    /// @notice Transfer WETH tokens on behalf of another address
    /// @param from Address to debit from
    /// @param to Address to credit to
    /// @param amount Amount of tokens to transfer
    /// @return success True if the transfer succeeded
    function transferFrom(address from, address to, uint256 amount) external returns (bool success) {
        require(balanceOf[from] >= amount, "Insufficient balance");
        require(allowance[from][msg.sender] >= amount, "Insufficient allowance");
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        allowance[from][msg.sender] -= amount;
        return true;
    }

    /// @notice Approve a spender to use tokens on the sender's behalf
    /// @param spender Address allowed to spend
    /// @param amount Amount they are allowed to spend
    /// @return success True if approval succeeded
    function approve(address spender, uint256 amount) external returns (bool success) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    /// @notice Mint mock WETH to a given address (testing only)
    /// @param to Address to receive tokens
    /// @param amount Amount of tokens to mint
    /// @dev This function does not exist in real WETH
    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }
}
