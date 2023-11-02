task(
  "deploy-hotpot-nft-factory",
  "Deploys HotpotNFTFactory contract"
).setAction(async (taskArgs, hre) => {
  console.log(`Deploying HotpotNFTFactory contract to ${network.name}`);

  if (network.name === "hardhat") {
    throw Error(
      'This command cannot be used on a local development chain.  Specify a valid network or simulate an Functions request locally with "npx hardhat functions-simulate".'
    );
  }
  const hotpotNftFactory = await ethers.getContractFactory("HotpotNFTFactory");
  const link = "0x326C977E6efc84E512bB9C30f76E30c160eD06FB";
  const wrapper = "0x2Ca8E0C643bDe4C2E08ab1fA0da3401AdAD7734D";
  const hotpotFactoryContract = await hotpotNftFactory.deploy(link, wrapper);

  console.log(
    `\nWaiting 3 blocks for transaction ${hotpotFactoryContract.deployTransaction.hash} to be confirmed...`
  );

  await hotpotFactoryContract.deployTransaction.wait(3);
  console.log(
    `HotpotNFTFactory deployed to ${hotpotFactoryContract.address} on ${network.name}`
  );
  console.log("\nVerifying contract...");
  try {
    await run("verify:verify", {
      address: hotpotFactoryContract.address,
      constructorArguments: [link, wrapper],
    });
    console.log("Contract verified");
  } catch (error) {
    if (!error.message.includes("Already Verified")) {
      console.log(
        "Error verifying contract.  Delete the build folder and try again."
      );
      console.log(error);
    } else {
      console.log("Contract already verified");
    }
  }
});
