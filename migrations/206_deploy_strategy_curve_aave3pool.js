// ============ Contracts ============

const Controller = artifacts.require('Controller')
const StrategyCurveAave3Pool = artifacts.require('StrategyCurveAave3Pool')
const VaultCurveAave3Pool = artifacts.require('VaultCurveAave3Pool')
const TokenMaster = artifacts.require('TokenMaster')

// ============ Main Migration ============

const migration = async (deployer, network, accounts) => {
  await Promise.all([
    deployStrategyCurveAave3Pool(deployer, network),
  ]);
};

module.exports = migration;

// ============ Deploy Functions ============

async function deployStrategyCurveAave3Pool(deployer, network) {
  const controller = await Controller.deployed();

  await deployer.deploy(
    StrategyCurveAave3Pool,
    controller.address
  )

  const vault = await VaultCurveAave3Pool.deployed();
  const strategy = await StrategyCurveAave3Pool.deployed()
  const tokenMaster = await TokenMaster.deployed();

  await controller.setStrategy(vault.address, strategy.address)
  await tokenMaster.add("100", vault.address, true)
}
