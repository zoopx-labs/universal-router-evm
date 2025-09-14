import { expect } from 'chai';
import { network } from 'hardhat';
import { parseUnits } from 'viem';

describe('Router', function () {
  it('should transfer and emit event', async function () {
    const conn = await network.connect();
    const { viem } = conn;

    const wallets = await viem.getWalletClients();
    const [deployer, user, target] = wallets;

    // Deploy MockERC20
  const { contract: mock } = await viem.sendDeploymentTransaction('MockERC20', ['Mock', 'MCK'], { client: { wallet: deployer } });

    // mint to user
    await mock.write.mint(user.address, parseUnits('1000', 18));

    // Deploy Router
  const { contract: router } = await viem.sendDeploymentTransaction('Router', [deployer.address, target.address, 1], { client: { wallet: deployer } });

    // user approves router
    await mock.connect(user).write.approve(router.target, parseUnits('100', 18));

    // Call universalBridgeTransfer from user
    const tx = await router.connect(user).write.universalBridgeTransfer(
      mock.target,
      parseUnits('100', 18),
      parseUnits('0.01', 18),
      parseUnits('0.01', 18),
      '0x',
      target.address,
      2,
      1
    );

    // Wait for tx to be mined
    const receipt = await tx.wait();
    const ev = receipt.logs?.find((l: any) => l.topics && l.topics.length > 0);
    expect(ev).to.not.equal(undefined);

    // Balances: target should have ~100 - fees
    const fee = parseUnits('0.01', 18);
    const targetBal = await mock.read.balanceOf(target.address);
    // numeric compare
    const expected = BigInt(parseUnits('100', 18)) - BigInt(fee) - BigInt(fee);
    expect(BigInt(targetBal)).to.equal(expected);
  });
});
