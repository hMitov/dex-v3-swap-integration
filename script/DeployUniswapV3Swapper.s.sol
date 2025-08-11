// SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;

import "forge-std/Script.sol";
import "./EnvLoader.s.sol";
import "../src/UniswapV3Swapper.sol";
import "v3-core/contracts/interfaces/IUniswapV3Factory.sol";

/**
 * @title DeployUniswapV3SwapperScript
 * @notice Foundry script for deploying the UniswapV3Swapper contract
 * @dev Loads deployment configuration (private key, router, factory, WETH) from environment variables
 */
contract DeployUniswapV3SwapperScript is EnvLoader {
    uint256 private privateKey;
    address private router;
    address private factory;
    address private weth;
    address private twapProvider;

    /**
     * @notice Executes the deployment process
     * @dev Loads environment variables, broadcasts the deployment transaction, and logs contract addresses
     */
    function run() external {
        loadEnvVars();

        vm.startBroadcast(privateKey);

        UniswapV3Swapper swapper = new UniswapV3Swapper(router, weth, twapProvider);

        vm.stopBroadcast();

        console.log("UniswapV3SwapIntegration deployed at:", address(swapper));
        console.log("SwapRouter address:", router);
        console.log("WETH address:", weth);
        console.log("TWAP Price Provider address:", twapProvider);
        console.log("Deployer:", privateKey);
    }

    /**
     * @notice Loads deployment configuration from environment variables
     * @dev Reads:
     * - DEPLOYER_PRIVATE_KEY: Private key of the deployer account
     * - SEPOLIA_SWAP_ROUTER_ADDRESS: Address of Uniswap V3 Swap Router
     * - SEPOLIA_FACTORY_ADDRESS: Address of Uniswap V3 Factory
     * - SEPOLIA_WETH_ADDRESS: Address of WETH contract
     */
    function loadEnvVars() internal override {
        privateKey = getEnvPrivateKey("DEPLOYER_PRIVATE_KEY");
        router = getEnvAddress("SEPOLIA_SWAP_ROUTER_ADDRESS");
        factory = getEnvAddress("SEPOLIA_FACTORY_ADDRESS");
        weth = getEnvAddress("SEPOLIA_WETH_ADDRESS");
        twapProvider = getEnvAddress("TWAP_PROVIDER_ADDRESS");
    }
}
