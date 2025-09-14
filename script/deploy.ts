import hre from 'hardhat';

async function main() {
  const { ethers } = hre as any;
  const signers = await ethers.getSigners();
  const deployer = signers[0];
  const deployerAddress = await deployer.getAddress();
  console.log('Deployer:', deployerAddress);

  const feeRecipient = process.env.FEE_RECIPIENT || deployerAddress;
  const defaultTarget = process.env.DEFAULT_TARGET || ethers.constants.AddressZero;
  const SRC_CHAIN_ID = Number(process.env.SRC_CHAIN_ID || 1);

  const Router = await ethers.getContractFactory('Router', deployer);
  const router = await Router.deploy(deployerAddress, feeRecipient, defaultTarget, SRC_CHAIN_ID);
  await router.deployed();
  console.log('Router deployed at:', router.address);

  // Optional post-deploy configuration from env
  const adapter = process.env.ADAPTER_ADDRESS || ethers.constants.AddressZero;
  const feeCollector = process.env.FEE_COLLECTOR || feeRecipient;
  const protocolFeeBps = Number(process.env.PROTOCOL_FEE_BPS || 0);
  const relayerFeeBps = Number(process.env.RELAYER_FEE_BPS || 0);
  const protocolShareBps = Number(process.env.PROTOCOL_SHARE_BPS || 0);
  const lpShareBps = Number(process.env.LP_SHARE_BPS || 0);

  if (adapter !== ethers.constants.AddressZero) {
    const tx = await router.setAdapter(adapter);
    await tx.wait();
    console.log('Adapter set to', adapter);
  }

  if (feeCollector && feeCollector !== ethers.constants.AddressZero) {
    const tx = await router.setFeeCollector(feeCollector);
    await tx.wait();
    console.log('Fee collector set to', feeCollector);
  }

  if (protocolFeeBps > 0) {
    const tx = await router.setProtocolFeeBps(protocolFeeBps);
    await tx.wait();
    console.log('Protocol fee bps set to', protocolFeeBps);
  }

  if (relayerFeeBps > 0) {
    const tx = await router.setRelayerFeeBps(relayerFeeBps);
    await tx.wait();
    console.log('Relayer fee bps set to', relayerFeeBps);
  }

  if (protocolShareBps > 0) {
    const tx = await router.setProtocolShareBps(protocolShareBps);
    await tx.wait();
    console.log('Protocol share bps set to', protocolShareBps);
  }

  if (lpShareBps > 0) {
    const tx = await router.setLPShareBps(lpShareBps);
    await tx.wait();
    console.log('LP share bps set to', lpShareBps);
  }
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
