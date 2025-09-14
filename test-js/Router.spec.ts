import { expect } from 'chai';
import { network } from 'hardhat';
import type { Hash } from 'viem';
import { parseUnits } from 'viem';

describe('Router', function () {
  it('should transfer and emit event', async function () {
    const conn = await network.connect();
    const { viem } = conn;

    const wallets = await viem.getWalletClients();
    const [deployer, user, target] = wallets;

  const { contract: mock } = await viem.sendDeploymentTransaction('MockERC20', ['Mock', 'MCK'], { client: { wallet: deployer } });
  await mock.write.mint([user.account.address, parseUnits('1000', 18)], { account: deployer.account });

  const { contract: router } = await viem.sendDeploymentTransaction('Router', [deployer.account.address, deployer.account.address, target.account.address, 1], { client: { wallet: deployer } });

  await mock.write.approve([router.address, parseUnits('100', 18)], { account: user.account });

  const txHash = await router.write.universalBridgeTransfer([
      mock.address,
      parseUnits('100', 18),
      parseUnits('0.01', 18),
      parseUnits('0.01', 18),
      '0x',
      target.account.address,
      2,
      1
    ], { account: user.account });
  const publicClient = await viem.getPublicClient();
  const receipt = await publicClient.waitForTransactionReceipt({ hash: txHash as Hash });
  const ev = receipt.logs?.[0];
    expect(ev).to.not.equal(undefined);

    const fee = parseUnits('0.01', 18);
  const targetBal = await mock.read.balanceOf([target.account.address]);
  const expected = BigInt(parseUnits('100', 18)) - BigInt(fee) - BigInt(fee);
  expect(BigInt(targetBal as unknown as bigint)).to.equal(expected);
  });
});
