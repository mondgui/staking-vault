// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @notice Reward coin paid by the staking vault. Only the owner can mint it.
contract RewardToken is ERC20, Ownable {
    constructor(address initialOwner) ERC20("Vault Reward", "RWD") Ownable(initialOwner) {}

    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }
}
