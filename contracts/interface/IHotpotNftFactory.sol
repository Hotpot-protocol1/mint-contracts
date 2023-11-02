pragma solidity ^0.8.19;

interface IHotpotNftFactory {

    struct InitializeParams{
        string name;
        string symbol;
        string metadata;
        address creator;
        uint256 mintStart;
        uint256 mintEnd;
        uint256 mintPerPerson;
        uint256 raffleTicketCost;
        uint256 mintCost;
        uint32 callbackGasLimit;
        uint128 claimWindow;
        uint16 numberOfWinners;
        address operator;
    }



    function isHopotNft(address nftContract) external view returns (bool);
}
