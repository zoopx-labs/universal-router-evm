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
  // constructor(address _admin, address _feeRecipient, address _defaultTarget, uint16 _srcChainId)
  const router = await Router.deploy(deployerAddress, feeRecipient, defaultTarget, SRC_CHAIN_ID);
  await router.deployed();
  console.log('Router deployed at:', router.address);

  // Optional post-deploy configuration from env
  // Support either a single ADAPTER_ADDRESS or a comma-separated list in ADAPTER_ADDRESSES
  const adapterEnv = process.env.ADAPTER_ADDRESSES || process.env.ADAPTER_ADDRESS;
  const adapters: string[] = adapterEnv
    ? adapterEnv.split(',').map(a => a.trim()).filter(a => a && a !== ethers.constants.AddressZero)
    : [];
  const feeCollector = process.env.FEE_COLLECTOR || feeRecipient;
  const protocolFeeBps = Number(process.env.PROTOCOL_FEE_BPS || 0);
  const relayerFeeBps = Number(process.env.RELAYER_FEE_BPS || 0);
  const protocolShareBps = Number(process.env.PROTOCOL_SHARE_BPS || 0);
  const lpShareBps = Number(process.env.LP_SHARE_BPS || 0);
  // Grant ADAPTER_ROLE for each provided adapter address
  if (adapters.length > 0) {
    for (const a of adapters) {
      const tx = await router.addAdapter(a);
      await tx.wait();
      console.log('Adapter role granted to', a);
    }
    // For backward compatibility populate deprecated single adapter storage with the first adapter (if any)
    try {
      const legacyTx = await router.setAdapter(adapters[0]);
      await legacyTx.wait();
      console.log('Legacy adapter slot set to', adapters[0]);
    } catch (e) {
      console.log('Legacy setAdapter call failed (expected if function removed in future):', (e as any).message || e);
    }
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
