// SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;

import "forge-std/Script.sol";
import "./EnvLoader.s.sol";
import "../src/TWAPPriceProvider.sol";

/**
 * @title DeployTWAPPriceProviderScript
 * @notice Foundry script for deploying the TWAPPriceProvider contract
 * @dev Loads deployer private key from environment variables and broadcasts deployment transaction
 */
contract DeployTWAPPriceProviderScript is EnvLoader {
    uint256 private privateKey;

    /**
     * @notice Executes the deployment script
     * @dev Loads environment variables, starts broadcasting, deploys TWAPPriceProvider, stops broadcasting
     */
    function run() external {
        loadEnvVars();

        vm.startBroadcast(privateKey);

        TWAPPriceProvider swapper = new TWAPPriceProvider();

        vm.stopBroadcast();

        console.log("TWAPPriceProvider deployed at:", address(swapper));
        console.log("Deployer:", privateKey);
    }

    /**
     * @notice Loads required environment variables
     * @dev Reads deployer private key from the "DEPLOYER_PRIVATE_KEY" env variable
     */
    function loadEnvVars() internal override {
        privateKey = getEnvPrivateKey("DEPLOYER_PRIVATE_KEY");
    }
}
