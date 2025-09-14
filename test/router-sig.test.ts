import { expect } from "chai";
import hre from "hardhat";
import { Wallet } from "ethers";
import { signRoute } from "../script/signRoute";
const { ethers } = hre;

describe("Router EIP-712 signed route flow", function () {
  it("should accept signed route and emit BridgeInitiated", async function () {
    const [deployer, relayer] = await ethers.getSigners();
    const provider = ethers.provider;

    const MockFactory = await ethers.getContractFactory("MockERC20", deployer);
    const token = await MockFactory.deploy("Mock", "MCK");
    await token.waitForDeployment?.();

    const RouterFactory = await ethers.getContractFactory("Router", deployer);
    const router = await RouterFactory.deploy(await deployer.getAddress(), ethers.ZeroAddress, 1);
    await router.waitForDeployment?.();

    // Create a random user wallet and fund it and mint tokens to it
    let userWallet = Wallet.createRandom();
    userWallet = userWallet.connect(provider as any);

    const amount = ethers.parseUnits("10", 18);
    // mint tokens to user
    await (await token.mint(await userWallet.getAddress(), amount)).wait?.();

    // fund user with ETH for approve gas
    await (await deployer.sendTransaction({ to: await userWallet.getAddress(), value: ethers.parseEther("1") })).wait?.();

    // user approves router
    const tokenAsUser = token.connect(userWallet as any);
    await (await tokenAsUser.approve(await router.getAddress(), amount)).wait?.();

    // Build args and intent
    const payload = ethers.toUtf8Bytes("hello");
    const payloadHash = ethers.keccak256(payload);
    const routeId = ethers.keccak256(ethers.toUtf8Bytes("routePlanExample"));

    const args = {
      token: await token.getAddress(),
      amount: amount,
      protocolFee: 0,
      relayerFee: 0,
      payload: payload,
      target: await relayer.getAddress(), // dummy target
      dstChainId: 2,
      nonce: 1,
    } as const;

    const intent = {
      routeId: routeId,
      token: await token.getAddress(),
      amount: amount.toString(),
      protocolFee: "0",
      relayerFee: "0",
      target: await relayer.getAddress(),
      dstChainId: 2,
      nonce: 1,
      expiry: Math.floor(Date.now() / 1000) + 3600,
      payloadHash: payloadHash,
      recipient: await userWallet.getAddress(),
    };

    // Sign the intent with the user's wallet
    const signature = await signRoute(userWallet as any, "Zoopx Router", "1", 31337, await router.getAddress(), intent as any);

    // relayer calls router with signature
    const routerAsRelayer = router.connect(relayer);
    const tx = await routerAsRelayer.universalBridgeTransferWithSig(args as any, intent as any, signature, await userWallet.getAddress());
    const rcpt = await tx.wait();
    const logs = rcpt.logs.map((l: any) => {
      try {
        return router.interface.parseLog(l);
      } catch (e) {
        return null;
      }
    }).filter(Boolean);
    // find BridgeInitiated
    const bridgeLog = logs.find((l: any) => l && l.name === 'BridgeInitiated');
    expect(bridgeLog).to.not.be.undefined;
    const argsEmitted = bridgeLog.args;
    expect(argsEmitted.user).to.equal(await userWallet.getAddress());
    expect(argsEmitted.token).to.equal(await token.getAddress());
    expect(argsEmitted.target).to.equal(await relayer.getAddress());
    expect(argsEmitted.amount).to.equal(amount - BigInt(0));
  });
});
