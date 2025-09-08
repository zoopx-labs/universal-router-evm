import { expect } from 'chai';
import { ethers } from 'hardhat';

describe('Router', function () {
  it('should transfer and emit event', async function () {
    const [deployer, user, target] = await ethers.getSigners();

    const Mock = await ethers.getContractFactory('MockERC20');
    const mock = await Mock.deploy('Mock', 'MCK');
    await mock.waitForDeployment();

    // mint to user
    await mock.mint(user.address, ethers.parseUnits('1000', 18));

    const Router = await ethers.getContractFactory('Router');
    const router = await Router.deploy(deployer.address, target.address, 1);
    await router.waitForDeployment();

    // user approves router
    await mock.connect(user).approve(await router.getAddress(), ethers.parseUnits('100', 18));

    const tx = await router.connect(user).universalBridgeTransfer(
      await mock.getAddress(),
      ethers.parseUnits('100', 18),
      ethers.parseUnits('0.01', 18), // protocolFee (small, arbitrary)
      ethers.parseUnits('0.01', 18), // relayerFee
      '0x',
      target.address,
      2,
      1
    );

    const receipt = await tx.wait();
    // Check event
    const ev = receipt.events?.find((e: any) => e.event === 'BridgeInitiated');
    expect(ev).to.not.equal(undefined);

    // Balances: target should have ~100 - fees
    const fee = ethers.parseUnits('0.01', 18);
    const targetBal = await mock.balanceOf(target.address);
    expect(targetBal).to.equal(ethers.parseUnits('100', 18) - fee - fee);
  });
});
