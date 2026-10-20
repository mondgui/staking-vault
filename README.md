# 03 — Staking vault

Stake Portfolio Token and earn a second reward token over time. Unstaking returns the deposit plus whatever reward has accrued. The staking token lives in this folder, so the project builds on its own.

## Why this one

Vaults are the module DeFi teams ask for by name: deposits, share accounting, rewards, and the fear of someone draining the contract. A vault you can explain is stronger on a resume than a long list of tutorials.

## You will be able to show

Tests for stake, unstake, and reward math, plus a testnet transaction where your reward balance actually increases.

## Stack

Solidity, Foundry, OpenZeppelin.

## Page

http://localhost:5175

From the portfolio folder, run `.\start-local-pages.ps1`. Click the four buttons in order. After 100 seconds, Bob's earned rewards should be about three times Alice's, because he deposited three times as much.

## Run

Foundry lives in `%USERPROFILE%\.foundry\bin`. Open a new terminal, then from this folder:

```bash
forge test
```

Ten tests cover two stakers, a late arrival, withdrawing only your deposit, claiming rewards, emergency withdrawal, and the owner's recovery limits.

To watch it on a local chain, start Anvil in one terminal:

```bash
anvil
```

In a second terminal, deploy. The sender is Anvil's public local account. It is not a wallet for real funds.

```bash
forge script script/Deploy.s.sol --rpc-url http://127.0.0.1:8545 --broadcast --unlocked --sender 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266
```

On a fresh Anvil chain the addresses are:

- Portfolio Token (the deposit): `0x5FbDB2315678afecb367f032d93F642f64180aa3`
- Vault Reward: `0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512`
- Staking vault: `0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0`

The vault streams rewards for 1,000 seconds. Funding 1,000 RWD pays 1 RWD per second, split by how much each person has staked.

A Base Sepolia deploy uses the same script. Put a testnet-only key in `.env` as `PRIVATE_KEY=0x...`, fund that address with Base Sepolia ETH, then:

```bash
forge script script/Deploy.s.sol --rpc-url base_sepolia --broadcast
```

`.env` is ignored by git. Do not put a key that holds real funds in it.

## Done when

- Two stakers earn in proportion to how much they deposited and how long they stayed.
- A user cannot withdraw more than they deposited.
- Reward funding and emergency withdrawal rules are explicit and tested.
