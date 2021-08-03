require("@nomiclabs/hardhat-waffle");

// This is a sample Hardhat task. To learn how to create your own go to
// https://hardhat.org/guides/create-task.html
task("accounts", "Prints the list of accounts", async () => {
  const accounts = await ethers.getSigners();

  for (const account of accounts) {
    console.log(account.address);
  }
});
// Go to https://www.alchemyapi.io, sign up, create
// a new App in its dashboard, and replace "KEY" with its key
const ALCHEMY_API_KEY = "dwVGTqLG99_hL0-v2rDlBySGmLAFX8d6";

// Replace this private key with your Ropsten account private key
// To export your private key from Metamask, open Metamask and
// go to Account Details > Export Private Key
// Be aware of NEVER putting real Ether into testing accounts
const ROPSTEN_PRIVATE_KEY = "";
// You need to export an object to set up your config
// Go to https://hardhat.org/config/ to learn more

/**
 * @type import('hardhat/config').HardhatUserConfig
 */
module.exports = {
  
  networks: {
    bsc_test: {
        url: 'https://data-seed-prebsc-1-s1.binance.org:8545/',
        //url: 'http://47.243.20.196:18545',
        //0x592394b6Bf10693ce473384356018660a83Ab6c7
        accounts: [""],
        saveDeployments: false
    },
    ht_test: {
        url: 'https://http-testnet.hecochain.com',
        //url: 'http://47.243.20.196:18545',
        accounts: [""],
        saveDeployments: false
    },
    ht_main: {
      url: 'https://http-mainnet.hecochain.com',
      //url: 'http://47.243.20.196:28545',
      accounts: [""],
      saveDeployments: false,
      gasPrice: 20000000000
      

  },

  ropsten: {
    url: `https://eth-ropsten.alchemyapi.io/v2/${ALCHEMY_API_KEY}`,
    accounts: [""]
    //accounts: [`0x${ROPSTEN_PRIVATE_KEY}`]
  }
},
    
  
  solidity: {
    compilers: [
      /*{
        version: "0.5.17",
        settings: {
          optimizer: {
            enabled: true,
            runs: 200
          }
        }
      },*/
      
      {
        version: "0.6.12",
        settings: {
          optimizer: {
            enabled: true,
            runs: 200
          }
        }
        
      },
      {
        version: "0.8.0",
        settings: {
          optimizer: {
            enabled: true,
            runs: 200
          }
        }
        
      }
    ]
  },
};

