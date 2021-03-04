import chai, { expect } from 'chai'
import { Contract } from 'ethers'
import { MaxUint256 } from 'ethers/constants'
import { BigNumber, bigNumberify, defaultAbiCoder, formatEther } from 'ethers/utils'
import { solidity, MockProvider, createFixtureLoader, deployContract } from 'ethereum-waffle'

import { expandTo18Decimals } from './shared/utilities'
import { getFixture } from './shared/fixtures'


chai.use(solidity)

const overrides = {
    gasLimit: 9999999,
    gasPrice: 0
}

describe('unitTest', () => {
    const provider = new MockProvider({
        hardfork: 'istanbul',
        mnemonic: 'horn horn horn horn horn horn horn horn horn horn horn horn',
        gasLimit: 9999999
    })
    const [wallet] = provider.getWallets()
    const loadFixture = createFixtureLoader(provider, [wallet])
    let ald: Contract
    let treasury: Contract
    let dao: Contract
    let tokenDistributor: Contract
    let rewardDistributor: Contract
    let controller: Contract
    let wrappedAld: Contract
    let tokenMaster: Contract
    let vault: Contract
    let strategyUSDTCompound: Contract
    let multiStakingRewards: Contract
    let usdt: Contract
    let comp: Contract
    beforeEach(async function () {
        const fixture = await loadFixture(getFixture)
        ald = fixture.ald
        treasury = fixture.treasury
        dao = fixture.dao
        tokenDistributor = fixture.tokenDistributor
        rewardDistributor = fixture.rewardDistributor
        controller = fixture.controller
        wrappedAld = fixture.wrappedAld
        tokenMaster = fixture.tokenMaster
        vault = fixture.vault
        strategyUSDTCompound = fixture.strategyUSDTCompound
        multiStakingRewards = fixture.multiStakingRewards
        usdt = fixture.usdt
        comp = fixture.comp
    })

    it('test distributeTokens', async () => {
        let mintAmount = 10000
        await ald.setMinter(wallet.address, true)
        await ald.mint(wallet.address, expandTo18Decimals(mintAmount)) // deployer
        console.log('minted ald')
        await ald.approve(wrappedAld.address, expandTo18Decimals(mintAmount))
        await wrappedAld.wrap(wallet.address, expandTo18Decimals(mintAmount))
        await wrappedAld.approve(rewardDistributor.address, expandTo18Decimals(mintAmount))
        await multiStakingRewards.addRewardPool(wrappedAld.address, 4 *  3600)
        await expect(
            rewardDistributor.distributeRewards([multiStakingRewards.address], [wrappedAld.address], [expandTo18Decimals(mintAmount)])
        )
        .to.emit(rewardDistributor, 'DistributedReward')
        .withArgs(wallet.address, multiStakingRewards.address, wrappedAld.address, expandTo18Decimals(mintAmount))
    })
})
