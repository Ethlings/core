const { BN } = require('@openzeppelin/test-helpers');
const { networks } = require('../truffle-config');

var ChangeToken = artifacts.require("ChangeToken");
var Wearables = artifacts.require("Wearables")
var Ethlings = artifacts.require("Ethlings")

const originals = require('../launch-wearables.json')

const WETH_ADDRESS = {
  mainnet: '0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619',
  mumbai_dummy: '0xfe4F5145f6e09952a5ba9e956ED0C25e3Fa4c7F1',
  mumbai: '0xA6FA4fB5f76172d178d61B04b0ecd319C5d1C0aa'
}

const delay = ms => new Promise(resolve => setTimeout(resolve, ms))

module.exports = async function(deployer) {
  await deployer.deploy(ChangeToken, (new BN('2223000')).mul(new BN('' + 10 ** 18)))
  await deployer.deploy(Wearables, 'https://api.ethlings.com/metadata/')
  await deployer.deploy(
    Ethlings, 
    'https://api.ethlings.com/metadata/', 
    WETH_ADDRESS['mumbai'], 
    ChangeToken.address, 
    Wearables.address
  )

  console.log('Setting Ethlings address on Token')
  let changeToken = await ChangeToken.deployed()
  await changeToken.setEthlingsAddress(Ethlings.address)
  console.log('Set Ethlings address on Token')
  console.log('Setting Ethlings address on Wearables')
  let wearables = await Wearables.deployed()
  await wearables.setController(Ethlings.address)
  console.log('Set Ethlings address on Wearables')
  
  await delay(60000)

  for (let x = 0; x < 11; x++) {
    console.log('Minting first batch of Wearbles in slot ' + x)
    const {slotList, scalarList, timestampList} = loadOriginals(x)
    for (let y = 0; y < slotList.length; y += 32) {
      await wearables.batchMint(slotList.slice(y, y + 32), scalarList.slice(y, y + 32), timestampList.slice(y, y + 32))
    }
    console.log('Minted first batch of Wearables in slot ' + x)
    if (x % 2 == 0) {
      await delay(60000)
    }
  }

  console.log('Minting skin 1')
  await wearables.batchMint([11], [2], [1655440627])
  console.log('Minted skin 1')

  await delay(60000)
};

const slotNames = {
  'background': 0,
  'legs': 1,
  'feet': 2,
  'leftArm': 3,
  'rightArm': 4,
  'chest': 5,
  'mouth': 6,
  'eyes': 7,
  'hair': 8,
  'hat': 9,
  'border': 10
}

function getRandomInt(max) {
  return Math.floor(Math.random() * max);
}

const loadOriginals = (slot) => {
  const time = Math.round(Date.now() / 1000)
  let slots = {}
  let scalars = {}
  let timestamps = {}
  for (let i in originals) {
    let original = originals[i]
    if (slotNames[original.slot] != slot)
      continue
    serial = getSerialFromId(original.originalId)
    slots[serial] = slot
    scalars[serial] = original.scalar
    if (serial <= 20) {
      timestamps[serial] = time
    } else {
      timestamps[serial] = Math.floor(time + (7 * 24 * 60 * 60) * (1 + getRandomInt(4)))
    }
  }

  slotList = []
  scalarList = []
  timestampList = []
  for (let i = 1; i < Object.keys(slots).length + 1; i++) {
    if (!(i in slots))
      console.log('uh oh', slot, i)
    slotList.push(slots[i])
    scalarList.push(scalars[i])
    timestampList.push(timestamps[i])
  }
  return {slotList, scalarList, timestampList}
}

const getSerialFromId = (id) => {
  while (id.slice(-4) == '0000') {
    id = id.substring(0, id.length - 4)
  }
  return parseInt('0x' + id.substring(id.length - 4, id.length), 16)
}