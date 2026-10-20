// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {PortfolioToken} from "../src/PortfolioToken.sol";
import {RewardToken} from "../src/RewardToken.sol";
import {StakingVault} from "../src/StakingVault.sol";

contract StakingVaultTest is Test {
    uint256 internal constant DURATION = 1_000;
    uint256 internal constant CAP = 1_000_000 ether;

    PortfolioToken internal staking;
    RewardToken internal reward;
    StakingVault internal vault;

    address internal owner = makeAddr("owner");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");

    function setUp() public {
        staking = new PortfolioToken(owner, CAP);
        reward = new RewardToken(owner);
        vault = new StakingVault(owner, staking, reward, DURATION);

        vm.startPrank(owner);
        staking.mint(alice, 1_000 ether);
        staking.mint(bob, 1_000 ether);
        vm.stopPrank();

        vm.prank(alice);
        staking.approve(address(vault), type(uint256).max);
        vm.prank(bob);
        staking.approve(address(vault), type(uint256).max);
    }

    function test_twoStakersEarnInProportionToTheirDeposit() public {
        _fund(1_000 ether);
        vm.prank(alice);
        vault.stake(100 ether);
        vm.prank(bob);
        vault.stake(300 ether);

        vm.warp(block.timestamp + 100);

        assertEq(vault.earned(alice), 25 ether);
        assertEq(vault.earned(bob), 75 ether);
    }

    function test_aLaterStakerEarnsOnlyForTheTimeTheyStayed() public {
        _fund(1_000 ether);
        vm.prank(alice);
        vault.stake(100 ether);

        vm.warp(block.timestamp + 100);

        vm.prank(bob);
        vault.stake(100 ether);
        vm.warp(block.timestamp + 100);

        assertEq(vault.earned(alice), 150 ether);
        assertEq(vault.earned(bob), 50 ether);
    }

    function test_withdrawReturnsTheDepositAndKeepsTheReward() public {
        _fund(1_000 ether);
        vm.prank(alice);
        vault.stake(100 ether);
        vm.warp(block.timestamp + 100);

        vm.prank(alice);
        vault.withdraw(40 ether);

        assertEq(staking.balanceOf(alice), 940 ether);
        assertEq(vault.balanceOf(alice), 60 ether);
        assertEq(vault.earned(alice), 100 ether);
        assertEq(staking.balanceOf(address(vault)), 60 ether);
    }

    function test_cannotWithdrawMoreThanDeposited() public {
        vm.prank(alice);
        vault.stake(100 ether);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(StakingVault.WithdrawExceedsDeposit.selector, 101 ether, 100 ether));
        vault.withdraw(101 ether);

        assertEq(vault.balanceOf(alice), 100 ether);
        assertEq(staking.balanceOf(alice), 900 ether);
    }

    function test_claimPaysTheRewardAndLeavesTheDeposit() public {
        _fund(1_000 ether);
        vm.prank(alice);
        vault.stake(100 ether);
        vm.warp(block.timestamp + 100);

        vm.prank(alice);
        vault.claim();

        assertEq(reward.balanceOf(alice), 100 ether);
        assertEq(vault.balanceOf(alice), 100 ether);
        assertEq(vault.earned(alice), 0);
    }

    function test_emergencyWithdrawReturnsTheDepositAndForfeitsRewards() public {
        _fund(1_000 ether);
        vm.prank(alice);
        vault.stake(100 ether);
        vm.prank(bob);
        vault.stake(300 ether);
        vm.warp(block.timestamp + 100);

        vm.prank(alice);
        vault.emergencyWithdraw();

        assertEq(staking.balanceOf(alice), 1_000 ether);
        assertEq(vault.balanceOf(alice), 0);
        assertEq(vault.earned(alice), 0);
        assertEq(vault.earned(bob), 75 ether);
        assertEq(staking.balanceOf(address(vault)), 300 ether);
    }

    function test_ownerCannotTakeDepositsOrReservedRewards() public {
        _fund(1_000 ether);
        vm.prank(alice);
        vault.stake(100 ether);
        vm.warp(block.timestamp + 100);

        vm.prank(owner);
        vm.expectRevert(StakingVault.CannotTakeStakedTokens.selector);
        vault.recoverMistakenToken(staking, owner, 1 ether);

        vm.prank(owner);
        vm.expectRevert(StakingVault.NoExcessRewards.selector);
        vault.recoverExcessRewards(owner);

        assertEq(vault.reservedRewards(), 1_000 ether);
        assertEq(staking.balanceOf(address(vault)), 100 ether);
    }

    function test_ownerCanRecoverRewardsNobodyEarned() public {
        _fund(1_000 ether);
        vm.warp(block.timestamp + DURATION);

        vm.prank(owner);
        vault.recoverExcessRewards(owner);

        assertEq(reward.balanceOf(owner), 1_000 ether);
        assertEq(reward.balanceOf(address(vault)), 0);
    }

    function test_ownerCanRecoverAMistakenThirdToken() public {
        PortfolioToken extra = new PortfolioToken(owner, CAP);
        vm.prank(owner);
        extra.mint(address(vault), 5 ether);

        vm.prank(owner);
        vault.recoverMistakenToken(extra, owner, 5 ether);

        assertEq(extra.balanceOf(owner), 5 ether);
    }

    function test_fundRejectsAnActivePeriodAndATinyAmount() public {
        _fund(1_000 ether);

        vm.prank(owner);
        vm.expectRevert(StakingVault.PeriodStillActive.selector);
        vault.fund(1_000 ether);

        vm.warp(block.timestamp + DURATION);
        vm.prank(owner);
        reward.mint(owner, 500);
        vm.prank(owner);
        reward.approve(address(vault), 500);
        vm.prank(owner);
        vm.expectRevert(StakingVault.AmountTooSmall.selector);
        vault.fund(500);
    }

    function _fund(uint256 amount) internal {
        vm.startPrank(owner);
        reward.mint(owner, amount);
        reward.approve(address(vault), amount);
        vault.fund(amount);
        vm.stopPrank();
    }
}
