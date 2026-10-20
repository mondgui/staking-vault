// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {PortfolioToken} from "../src/PortfolioToken.sol";
import {RewardToken} from "../src/RewardToken.sol";
import {StakingVault} from "../src/StakingVault.sol";

/// @notice Deploys Portfolio Token, Vault Reward, and a vault that streams rewards over 1,000 seconds.
contract Deploy is Script {
    uint256 internal constant CAP = 1_000_000 ether;
    uint256 internal constant DURATION = 1_000;

    function run() external {
        address deployer = msg.sender;
        if (vm.envExists("PRIVATE_KEY")) {
            uint256 deployerKey = vm.envUint("PRIVATE_KEY");
            deployer = vm.addr(deployerKey);
            vm.startBroadcast(deployerKey);
        } else {
            vm.startBroadcast(deployer);
        }

        PortfolioToken staking = new PortfolioToken(deployer, CAP);
        RewardToken reward = new RewardToken(deployer);
        StakingVault vault = new StakingVault(deployer, staking, reward, DURATION);

        vm.stopBroadcast();

        console.log("StakingToken", address(staking));
        console.log("RewardToken", address(reward));
        console.log("StakingVault", address(vault));
    }
}
