require('dotenv').config()

module.exports = {
  networks: {
    development: {
      protocol: 'http',
      host: 'localhost',
      port: 8545,
      gas: 5000000,
      gasPrice: 5e9,
      networkId: '*',
    },
    matic: {
      protocol: 'http',
      host: process.env.MATIC_PROVIDER,
      gasPrice: 10e9,
      network_id: 137
    }
  },
};
