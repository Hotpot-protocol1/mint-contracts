// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import "./HotpotNFTContract.sol";
import {IHotpotNftFactory} from "./interface/IHotpotNftFactory.sol";

contract NFTFactory is Ownable {
    address[] public nftContracts;
    mapping(address=>bool) public isNft;

    event NFTCollectionCreated(string name,string symbol,address _nftCollection,address creator);

    function deployNFTCollection(
        IHotpotNftFactory.InitializeParams memory params
    ) external payable returns (address _nftCollection) {
        HotpotNFTContract _nft = new HotpotNFTContract(params);
        _nftCollection = address(_nft);
        nftContracts.push(_nftCollection);
        emit NFTCollectionCreated(params.name, params.symbol, _nftCollection, params.creator);
    }
}
    