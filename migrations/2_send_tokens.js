const { BN } = require('@openzeppelin/test-helpers');
require('dotenv').config()

var Wearables = artifacts.require("Wearables")
const WEARABLES_ADDRESS = process.env.WEARABLES_ADDRESS

const recipients = require('./recipients')

const delay = ms => new Promise(resolve => setTimeout(resolve, ms))

module.exports = async (deployer, network, accounts) => {
  let wearables = await Wearables.at(WEARABLES_ADDRESS)
  const name = await wearables.name()
  console.log(name)
  for (let recipient in recipients) {
    if (recipient == '0x0000000000000000000000000000000000000000') continue
    try {
      console.log(recipient)
      let ids = []
      let amounts = []
      for (let tokenId in recipients[recipient]) {
        ids.push(new BN(tokenId))
        amounts.push(new BN(recipients[recipient][tokenId]))
      }
      console.log(ids, amounts)
      await wearables.safeBatchTransferFrom(accounts[0], recipient, ids, amounts, [])
      await delay(1000)
    } catch (e) {
      console.log(e)
    }
    
  }
}