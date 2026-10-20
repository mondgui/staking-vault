import "./style.css";
import {
  BaseError,
  ContractFunctionRevertedError,
  createPublicClient,
  createWalletClient,
  http,
  parseEther,
  type Address,
} from "viem";
import { foundry } from "viem/chains";

const OWNER = "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266" as Address;
const ALICE = "0x70997970C51812dc3A010C7d01b50e0d17dc79C8" as Address;
const BOB = "0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC" as Address;

const publicClient = createPublicClient({ chain: foundry, transport: http("/rpc") });

function signer(account: Address) {
  return createWalletClient({ account, chain: foundry, transport: http("/rpc") });
}

const erc20 = [
  {
    type: "function",
    name: "mint",
    stateMutability: "nonpayable",
    inputs: [
      { name: "to", type: "address" },
      { name: "amount", type: "uint256" },
    ],
    outputs: [],
  },
  {
    type: "function",
    name: "approve",
    stateMutability: "nonpayable",
    inputs: [
      { name: "spender", type: "address" },
      { name: "amount", type: "uint256" },
    ],
    outputs: [{ type: "bool" }],
  },
] as const;

const vaultAbi = [
  { type: "function", name: "duration", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
  {
    type: "function",
    name: "balanceOf",
    stateMutability: "view",
    inputs: [{ name: "account", type: "address" }],
    outputs: [{ type: "uint256" }],
  },
  {
    type: "function",
    name: "earned",
    stateMutability: "view",
    inputs: [{ name: "account", type: "address" }],
    outputs: [{ type: "uint256" }],
  },
  {
    type: "function",
    name: "stake",
    stateMutability: "nonpayable",
    inputs: [{ name: "amount", type: "uint256" }],
    outputs: [],
  },
  {
    type: "function",
    name: "fund",
    stateMutability: "nonpayable",
    inputs: [{ name: "amount", type: "uint256" }],
    outputs: [],
  },
  { type: "error", name: "PeriodStillActive", inputs: [] },
  { type: "error", name: "AmountTooSmall", inputs: [] },
] as const;

function coins(value: bigint): string {
  const rounded = (value + 50_000_000_000_000n) / 100_000_000_000_000n;
  const whole = rounded / 10_000n;
  const frac = (rounded % 10_000n).toString().padStart(4, "0").replace(/0+$/, "");
  return frac ? `${whole}.${frac}` : `${whole}`;
}

function explain(error: unknown): string {
  if (error instanceof BaseError) {
    const reverted = error.walk((item) => item instanceof ContractFunctionRevertedError);
    if (reverted instanceof ContractFunctionRevertedError) {
      const name = reverted.data?.errorName;
      if (name === "PeriodStillActive") return "Rewards are already streaming. Stake, then advance time.";
      return `Rejected (${name ?? "the contract stopped the call"}).`;
    }
    return "The local chain is not running. Start it, then refresh this page.";
  }
  if (error instanceof Error && error.message) return error.message;
  return "The local chain is not running. Start it, then refresh this page.";
}

const status = document.querySelector("#status") as HTMLParagraphElement;
const aliceStake = document.querySelector("#alice-stake") as HTMLParagraphElement;
const bobStake = document.querySelector("#bob-stake") as HTMLParagraphElement;
const aliceEarned = document.querySelector("#alice-earned") as HTMLParagraphElement;
const bobEarned = document.querySelector("#bob-earned") as HTMLParagraphElement;
const note = document.querySelector("#note") as HTMLParagraphElement;
const buttons = [...document.querySelectorAll("button")];

let staking: Address;
let reward: Address;
let vault: Address;

function setNote(text: string, kind: "" | "ok" | "error") {
  note.textContent = text;
  note.className = kind ? `note ${kind}` : "note";
}

async function refresh() {
  const [aliceDeposit, bobDeposit, aliceReward, bobReward] = await Promise.all([
    publicClient.readContract({ address: vault, abi: vaultAbi, functionName: "balanceOf", args: [ALICE] }),
    publicClient.readContract({ address: vault, abi: vaultAbi, functionName: "balanceOf", args: [BOB] }),
    publicClient.readContract({ address: vault, abi: vaultAbi, functionName: "earned", args: [ALICE] }),
    publicClient.readContract({ address: vault, abi: vaultAbi, functionName: "earned", args: [BOB] }),
  ]);
  aliceStake.textContent = coins(aliceDeposit);
  bobStake.textContent = coins(bobDeposit);
  aliceEarned.textContent = coins(aliceReward);
  bobEarned.textContent = coins(bobReward);
  status.textContent = "Connected to the local chain.";
}

async function rpc(method: string, params: unknown[]) {
  const response = await fetch("/rpc", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ jsonrpc: "2.0", id: 1, method, params }),
  });
  const body = (await response.json()) as { error?: { message: string } };
  if (body.error) throw new Error(body.error.message);
}

async function moveChain(seconds: number) {
  const block = await publicClient.getBlock();
  await rpc("evm_setNextBlockTimestamp", [Number(block.timestamp) + seconds]);
}

async function send(account: Address, address: Address, abi: typeof erc20 | typeof vaultAbi, functionName: string, args: readonly unknown[]) {
  const request = { account, address, abi, functionName, args };
  await publicClient.simulateContract(request as never);
  await moveChain(1);
  const hash = await signer(account).writeContract(request as never);
  const receipt = await publicClient.waitForTransactionReceipt({ hash });
  if (receipt.status === "reverted") throw new Error("The transaction reverted.");
}

async function run(action: () => Promise<string>) {
  buttons.forEach((button) => {
    button.disabled = true;
  });
  setNote("Sending…", "");
  try {
    const message = await action();
    await refresh();
    setNote(message, "ok");
  } catch (error) {
    setNote(explain(error), "error");
  } finally {
    buttons.forEach((button) => {
      button.disabled = false;
    });
  }
}

async function stake(account: Address, amount: bigint) {
  await send(OWNER, staking, erc20, "mint", [account, amount]);
  await send(account, staking, erc20, "approve", [vault, amount]);
  await send(account, vault, vaultAbi, "stake", [amount]);
}

document.querySelector("#fund")!.addEventListener("click", () =>
  run(async () => {
    const duration = await publicClient.readContract({ address: vault, abi: vaultAbi, functionName: "duration" });
    const amount = duration * 10n ** 18n;
    await send(OWNER, reward, erc20, "mint", [OWNER, amount]);
    await send(OWNER, reward, erc20, "approve", [vault, amount]);
    await send(OWNER, vault, vaultAbi, "fund", [amount]);
    return "Rewards are streaming at 1 RWD per second. Stake, then advance time.";
  }),
);

document.querySelector("#alice")!.addEventListener("click", () =>
  run(async () => {
    await stake(ALICE, parseEther("100"));
    return "Alice deposited 100 PTK.";
  }),
);

document.querySelector("#bob")!.addEventListener("click", () =>
  run(async () => {
    await stake(BOB, parseEther("300"));
    return "Bob deposited 300 PTK.";
  }),
);

document.querySelector("#advance")!.addEventListener("click", () =>
  run(async () => {
    await moveChain(100);
    await rpc("evm_mine", []);
    return "The chain moved forward 100 seconds. Rewards above are what the vault owes right now.";
  }),
);

const loaded = (await fetch("/addresses.json", { cache: "no-store" }).then((response) => response.json())) as {
  staking: Address;
  reward: Address;
  vault: Address;
};
staking = loaded.staking;
reward = loaded.reward;
vault = loaded.vault;

if (vault === "0x0000000000000000000000000000000000000000") {
  status.textContent = "The vault is not on the local chain yet. Run start-local-pages.ps1 from the portfolio folder.";
} else {
  try {
    await refresh();
  } catch (error) {
    status.textContent = explain(error);
  }
}
