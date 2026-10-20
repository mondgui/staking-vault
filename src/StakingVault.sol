// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title Staking vault
/// @notice Stake Portfolio Token, earn Vault Reward over time. A larger deposit held for longer earns more. The owner can fund rewards, but cannot take deposits.
contract StakingVault is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint256 private constant PRECISION = 1e18;

    IERC20 public immutable stakingToken;
    IERC20 public immutable rewardToken;
    uint256 public immutable duration;

    uint256 public rewardRate;
    uint256 public periodFinish;
    uint256 public lastUpdateTime;
    uint256 public rewardPerTokenStored;
    uint256 public totalRewardAccounted;
    uint256 public totalRewardPaid;
    uint256 public totalSupply;

    mapping(address account => uint256 balance) public balanceOf;
    mapping(address account => uint256 paid) public userRewardPerTokenPaid;
    mapping(address account => uint256 amount) public rewards;

    error ZeroAddress();
    error SameToken();
    error ZeroAmount();
    error PeriodStillActive();
    error AmountTooSmall();
    error WithdrawExceedsDeposit(uint256 requested, uint256 deposited);
    error NothingToClaim();
    error NothingStaked();
    error CannotTakeStakedTokens();
    error UseRecoverExcessRewards();
    error NoExcessRewards();

    constructor(address initialOwner, IERC20 stakingToken_, IERC20 rewardToken_, uint256 duration_) Ownable(initialOwner) {
        if (initialOwner == address(0) || address(stakingToken_) == address(0) || address(rewardToken_) == address(0)) {
            revert ZeroAddress();
        }
        if (address(stakingToken_) == address(rewardToken_)) revert SameToken();
        if (duration_ == 0) revert ZeroAmount();

        stakingToken = stakingToken_;
        rewardToken = rewardToken_;
        duration = duration_;
    }

    /// @notice Move `amount` of the staking token into the vault.
    function stake(uint256 amount) external nonReentrant {
        if (amount == 0) revert ZeroAmount();
        _updateReward(msg.sender);
        totalSupply += amount;
        balanceOf[msg.sender] += amount;
        stakingToken.safeTransferFrom(msg.sender, address(this), amount);
    }

    /// @notice Take back `amount` of the deposit. Rewards stay claimable.
    function withdraw(uint256 amount) external nonReentrant {
        if (amount == 0) revert ZeroAmount();
        if (amount > balanceOf[msg.sender]) revert WithdrawExceedsDeposit(amount, balanceOf[msg.sender]);
        _updateReward(msg.sender);
        totalSupply -= amount;
        balanceOf[msg.sender] -= amount;
        stakingToken.safeTransfer(msg.sender, amount);
    }

    /// @notice Send the caller's earned reward tokens.
    function claim() external nonReentrant {
        _updateReward(msg.sender);
        uint256 payout = rewards[msg.sender];
        if (payout == 0) revert NothingToClaim();
        rewards[msg.sender] = 0;
        totalRewardPaid += payout;
        rewardToken.safeTransfer(msg.sender, payout);
    }

    /// @notice Return the full deposit immediately and give up unclaimed rewards.
    function emergencyWithdraw() external nonReentrant {
        _updateReward(msg.sender);
        uint256 amount = balanceOf[msg.sender];
        if (amount == 0) revert NothingStaked();

        uint256 forfeited = rewards[msg.sender];
        rewards[msg.sender] = 0;
        totalRewardAccounted -= forfeited;
        totalSupply -= amount;
        balanceOf[msg.sender] = 0;
        stakingToken.safeTransfer(msg.sender, amount);
    }

    /// @notice Pull reward tokens from the owner and stream them evenly until `duration` elapses. Reverts while a period is still running.
    function fund(uint256 amount) external onlyOwner nonReentrant {
        if (block.timestamp < periodFinish) revert PeriodStillActive();
        _updateReward(address(0));

        uint256 rate = amount / duration;
        if (rate == 0) revert AmountTooSmall();
        uint256 funded = rate * duration;

        rewardRate = rate;
        lastUpdateTime = block.timestamp;
        periodFinish = block.timestamp + duration;
        rewardToken.safeTransferFrom(msg.sender, address(this), funded);
    }

    /// @notice Send the owner reward tokens that no staker is still entitled to. Deposits cannot be taken.
    function recoverExcessRewards(address to) external onlyOwner nonReentrant {
        if (to == address(0)) revert ZeroAddress();
        _updateReward(address(0));
        uint256 reserved = reservedRewards();
        uint256 balance = rewardToken.balanceOf(address(this));
        if (balance <= reserved) revert NoExcessRewards();
        rewardToken.safeTransfer(to, balance - reserved);
    }

    /// @notice Send a token that was transferred here by mistake. The staking token and the reward token are refused.
    function recoverMistakenToken(IERC20 token, address to, uint256 amount) external onlyOwner nonReentrant {
        if (to == address(0)) revert ZeroAddress();
        if (address(token) == address(stakingToken)) revert CannotTakeStakedTokens();
        if (address(token) == address(rewardToken)) revert UseRecoverExcessRewards();
        if (amount == 0) revert ZeroAmount();
        token.safeTransfer(to, amount);
    }

    function earned(address account) public view returns (uint256) {
        return (balanceOf[account] * (rewardPerToken() - userRewardPerTokenPaid[account])) / PRECISION + rewards[account];
    }

    function rewardPerToken() public view returns (uint256) {
        if (totalSupply == 0) return rewardPerTokenStored;
        uint256 elapsed = lastTimeRewardApplicable() - lastUpdateTime;
        return rewardPerTokenStored + (elapsed * rewardRate * PRECISION) / totalSupply;
    }

    function lastTimeRewardApplicable() public view returns (uint256) {
        return block.timestamp < periodFinish ? block.timestamp : periodFinish;
    }

    /// @notice Reward tokens that must stay in the vault: what stakers have earned, plus what current stakers can still earn before the period ends.
    function reservedRewards() public view returns (uint256) {
        uint256 applicable = lastTimeRewardApplicable();
        uint256 elapsed = applicable - lastUpdateTime;
        uint256 pendingEarned = totalSupply == 0 || elapsed == 0 ? 0 : elapsed * rewardRate;
        uint256 stillStreaming = periodFinish > applicable ? rewardRate * (periodFinish - applicable) : 0;
        return totalRewardAccounted + pendingEarned + stillStreaming - totalRewardPaid;
    }

    function _updateReward(address account) private {
        uint256 elapsed = lastTimeRewardApplicable() - lastUpdateTime;
        if (elapsed > 0 && totalSupply > 0) {
            totalRewardAccounted += elapsed * rewardRate;
            rewardPerTokenStored += (elapsed * rewardRate * PRECISION) / totalSupply;
        }
        lastUpdateTime = lastTimeRewardApplicable();

        if (account != address(0)) {
            rewards[account] = earned(account);
            userRewardPerTokenPaid[account] = rewardPerTokenStored;
        }
    }
}
