// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {ERC20Capped} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Capped.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @title Portfolio Token
/// @notice Fixed-format coin for the later vault and exchange. Only the owner can create tokens, and the supply can never pass the cap. Holders can destroy their own tokens.
contract PortfolioToken is ERC20, ERC20Burnable, ERC20Capped, Ownable {
    constructor(address initialOwner, uint256 cap_)
        ERC20("Portfolio Token", "PTK")
        ERC20Capped(cap_)
        Ownable(initialOwner)
    {}

    /// @notice Create `amount` tokens for `to`. Reverts if the caller is not the owner or if the cap would be passed.
    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }

    /// @dev ERC20Capped checks the supply whenever tokens are created. This joins that check with the normal transfer update.
    function _update(address from, address to, uint256 value) internal override(ERC20, ERC20Capped) {
        super._update(from, to, value);
    }
}
