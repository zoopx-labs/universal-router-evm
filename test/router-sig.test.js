const { expect } = require("chai");
const hre = require("hardhat");
const { ethers } = hre;

describe("Router EIP-712 signed route flow (js)", function () {
  it("should accept signed route and emit BridgeInitiated", async function () {
    const [deployer, relayer] = await ethers.getSigners();

    const MockFactory = await ethers.getContractFactory("MockERC20", deployer);
    const token = await MockFactory.deploy("Mock", "MCK");
    await token.deployed();

    const RouterFactory = await ethers.getContractFactory("Router", deployer);
    const router = await RouterFactory.deploy(await deployer.getAddress(), ethers.ZeroAddress, 1);
    await router.deployed();

    // Create a random user wallet and fund it and mint tokens to it
    const userWallet = ethers.Wallet.createRandom().connect(ethers.provider);

    const amount = ethers.parseUnits("10", 18);
    // mint tokens to user
    await (await token.mint(await userWallet.getAddress(), amount)).wait();

    // fund user with ETH for gas
    await (await deployer.sendTransaction({ to: await userWallet.getAddress(), value: ethers.parseEther("1") })).wait();

    // user approves router
    const tokenAsUser = token.connect(userWallet);
    await (await tokenAsUser.approve(await router.getAddress(), amount)).wait();

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
    };

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

    const domain = {
      name: "Zoopx Router",
      version: "1",
      chainId: 31337,
      verifyingContract: await router.getAddress(),
    };

    const types = {
      RouteIntent: [
        { name: "routeId", type: "bytes32" },
        { name: "token", type: "address" },
        { name: "amount", type: "uint256" },
        { name: "protocolFee", type: "uint256" },
        { name: "relayerFee", type: "uint256" },
        { name: "target", type: "address" },
        { name: "dstChainId", type: "uint256" },
        { name: "nonce", type: "uint256" },
        { name: "expiry", type: "uint256" },
        { name: "payloadHash", type: "bytes32" },
        { name: "recipient", type: "address" },
      ],
    };

    // Sign the intent with the user's wallet
    const signature = await userWallet._signTypedData(domain, types, intent);

    // relayer calls router with signature
    const routerAsRelayer = router.connect(relayer);
    const tx = await routerAsRelayer.universalBridgeTransferWithSig(args, intent, signature, await userWallet.getAddress());
    const rcpt = await tx.wait();
    const parsed = rcpt.logs.map((l) => {
      try {
        return router.interface.parseLog(l);
      } catch (e) {
        return null;
      }
    }).filter(Boolean);
    const bridgeLog = parsed.find((l) => l && l.name === 'BridgeInitiated');
    expect(bridgeLog).to.not.be.undefined;
  });
});
