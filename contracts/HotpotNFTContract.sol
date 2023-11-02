// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./interface/IHotpotNftFactory.sol";
import {VRFV2WrapperConsumerBase} from "@chainlink/contracts/src/v0.8/VRFV2WrapperConsumerBase.sol";

contract HotpotNFTContract is ERC721, ERC721URIStorage, Ownable, VRFV2WrapperConsumerBase {

    string public contractMetadata;

    uint256 private _nextTokenId;
    uint256 private _mintCounter;

    uint256 public mintPerPerson;
    uint256 public mintStart;
    uint256 public mintEnd;

    uint256 public rafflePrice;
    uint256 public mintPrice;
    uint256 public mintFunds;
    uint256 public potFunds;
    
    uint32 public callbackGasLimit;
    uint32 public lastRaffleTicketId;
    uint32 public potTicketIdStart;
    uint32 public potTicketIdEnd;
    uint32 public numberOfWinners;
    uint16 public currentPotId;

    address public creator;
    address public operator;

    struct Prize{
        uint128 amount;
        uint128 deadline;
    }

    struct RequestStatus {
        bool fullfilled;
        bool exists;
        uint256 randomWord;
    }

    mapping(address => Prize) public claimablePrizes;
    mapping(uint256 => RequestStatus) public chainlinkRequests;
    mapping(uint16 => uint32[]) public winningTicketIds;
    mapping(uint16 => uint128) public prizeAmounts; // winner id => prize amount. For example, first winner gets 5ETH, second winner - 1 ETH, etc.
    uint256[] public requestIds;
    uint256 public lastRequestId;
    uint128 private claimWindow;

    event RandomWordRequested(
        uint256 requestId,
        uint32 fromTicketId,
        uint32 toTicketId
    );

    event WinnersAssigned(address[] _winners);

    event GenerateRaffleTickets(
        address indexed _buyer,
        uint32 _buyerTicketIdStart,
        uint32 _buyerTicketIdEnd
    );

    event Claim(address indexed user, uint256 amount);

    event RandomnessFulfilled(uint16 potId, uint256 randomWord);
    constructor(
        address _link,
        address _vrfV2Wrapper,
        IHotpotNftFactory.InitializeParams memory params
    ) VRFV2WrapperConsumerBase(_link, _vrfV2Wrapper) ERC721(params.name, params.symbol) {
        contractMetadata = params.metadata;
        creator = params.creator;
        mintStart = params.mintStart;
        mintEnd = params.mintEnd;
        mintPerPerson = params.mintPerPerson;
        rafflePrice = params.raffleTicketCost;
        mintPrice = params.mintCost;
        numberOfWinners = params.numberOfWinners;
        operator=params.operator;
        callbackGasLimit = params.callbackGasLimit;
        claimWindow = params.claimWindow;
        _nextTokenId=0;
        _mintCounter=0;
        currentPotId=1;
        _transferOwnership(params.creator);
    }

    modifier onlyOperator()
    {
        require(msg.sender==operator,"only operator");
        _;
    }


    function uploadNFTs(string[] memory tokenURIs) public onlyOwner {
        for (uint256 i = 0; i < tokenURIs.length; i++) {
            _safeMint(address(this), _nextTokenId);
            _setTokenURI(_nextTokenId, tokenURIs[i]);
            _nextTokenId++;
        }
    }

    function safeMint(uint32 amount) public payable {
        require(
            msg.value >= amount * (rafflePrice + mintPrice),
            "Insufficient funds"
        );
        require(block.timestamp >= mintStart, "Mint not started");
        require(block.timestamp <= mintEnd, "Mint ended");
        require(
            amount + balanceOf(msg.sender) <= mintPerPerson,
            "You have reached the mint limit"
        );
        require(_mintCounter+amount<=_nextTokenId,"required NFT amount not created yet");
        for(uint32 i=0;i<amount;i++){
            _safeTransfer(address(this),msg.sender,_mintCounter,"");
            _mintCounter++;
        }
        mintFunds += (msg.value - amount * rafflePrice);
        _generateTickets(amount, msg.sender);
    }

    function finishRaffle() public onlyOperator {
        require(block.timestamp > mintEnd, "Mint not ended");
        require(requestIds.length == 0, "Raffle already triggered");
        require(_mintCounter==_nextTokenId,"required NFT amount not created yet");
        _requestRandomWinners();
    }
    
    function _requestRandomWinners() internal {
        uint32 _gasLimit = callbackGasLimit;
        require(_gasLimit > 0, "Gas limit not specified");
        uint256 requestId = requestRandomness(_gasLimit, 3, 1); // TODO if you deploy on Polygon, increase confirmation blocks (check out reorgs)
        chainlinkRequests[requestId].exists = true;
        lastRequestId = requestId;
        requestIds.push(requestId);
        emit RandomWordRequested(requestId, potTicketIdStart, potTicketIdEnd);
    }


    function executeRaffle(address[] calldata _winners) external onlyOperator {
        require(
            _winners.length == numberOfWinners,
            "Must be equal to numberofWinners"
        );
        require(address(this).balance >= _mintCounter*rafflePrice, "The pot is not filled");

        uint sum = 0;
        for (uint16 i; i < _winners.length; i++) {
            uint128 _prizeAmount = prizeAmounts[i];
            Prize storage userPrize = claimablePrizes[_winners[i]];
            userPrize.deadline = uint128(block.timestamp + claimWindow);
            userPrize.amount = userPrize.amount + _prizeAmount;
            sum += _prizeAmount;
        }
        require(sum <= _mintCounter*rafflePrice);

        emit WinnersAssigned(_winners);
    }

    function _generateTickets(uint32 amount,address minter)internal{
        uint32 minterTicketIdStart;
        uint32 minterTicketIdEnd;

        if(amount>0)
        {
            minterTicketIdStart = lastRaffleTicketId + 1;
            minterTicketIdEnd = lastRaffleTicketId + amount -1;
        }
        lastRaffleTicketId+=amount;

        emit GenerateRaffleTickets(minter,minterTicketIdStart,minterTicketIdEnd);
    } 

  function fulfillRandomWords(uint256 _requestId, uint256[] memory _randomWords) internal override {
        uint256 randomWord = _randomWords[0];
        uint32 rangeFrom = potTicketIdStart;
        uint32 rangeTo = potTicketIdEnd;

        chainlinkRequests[_requestId] = RequestStatus({
            fullfilled: true,
            exists: true,
            randomWord: randomWord
        });

        uint256 n_winners = numberOfWinners;
        uint32[] memory derivedRandomWords = new uint32[](n_winners);
        derivedRandomWords[0] = _normalizeValueToRange(randomWord, rangeFrom, rangeTo);
        uint256 nextRandom;
        uint32 nextRandomNormalized;
        for (uint256 i = 1; i < n_winners; i++) {
            nextRandom = uint256(keccak256(abi.encode(randomWord, i)));
            nextRandomNormalized = _normalizeValueToRange(nextRandom, rangeFrom, rangeTo);
            derivedRandomWords[i] = _incrementRandomValueUntilUnique(
                nextRandomNormalized,
                derivedRandomWords,
                rangeFrom,
                rangeTo
            );
        }

        winningTicketIds[currentPotId] = derivedRandomWords;
        emit RandomnessFulfilled(currentPotId, randomWord);
        currentPotId++;
    }

    function _normalizeValueToRange(
        uint256 _value, uint32 _rangeFrom, uint32 _rangeTo
    ) internal pure returns(uint32 _scaledValue) {
        _scaledValue = uint32(_value) % (_rangeTo - _rangeFrom) + _rangeFrom; // from <= x <= to
    }

    function _incrementRandomValueUntilUnique(
        uint32 _random, 
        uint32[] memory _randomWords, 
        uint32 _rangeFrom,
        uint32 _rangeTo
    ) internal pure returns(uint32 _uniqueRandom) {
        _uniqueRandom = _random;
        for(uint i = 0; i < _randomWords.length;) {
            if(_uniqueRandom == _randomWords[i]) {
                unchecked {
                    _uniqueRandom = _normalizeValueToRange(
                        _uniqueRandom + 1,
                        _rangeFrom,
                        _rangeTo
                    );
                    i = 0;
                }
            }
            else {
                unchecked {
                    i++;
                }
            }
        }
    }

    function claim() external  {
        address payable user = payable(msg.sender);
        Prize memory prize = claimablePrizes[user];
        require(prize.amount > 0, "No available winnings");
        require(block.timestamp < prize.deadline, "Claim window is closed");

        claimablePrizes[user].amount = 0;
        user.transfer(prize.amount);
        emit Claim(user, prize.amount);
    }

    function canClaim(address user) external view returns (bool) {
        Prize memory prize = claimablePrizes[user];
        return prize.amount > 0 && block.timestamp < prize.deadline;
    }

    function getWinningTicketIds(
        uint16 _potId
    ) external view returns (uint32[] memory) {
        return winningTicketIds[_potId];
    }


    function setCreator(address _creator) public onlyOwner {
        creator = _creator;
        _transferOwnership(creator);
    }

    function setOperator(address _operator) public onlyOperator {
        operator = _operator;
    }

    // The following functions are overrides required by Solidity.

    function tokenURI(
        uint256 tokenId
    ) public view override(ERC721, ERC721URIStorage) returns (string memory) {
        return super.tokenURI(tokenId);
    }

    function supportsInterface(
        bytes4 interfaceId
    ) public view override(ERC721, ERC721URIStorage) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    function claimFunds() public onlyOwner {
        payable(msg.sender).transfer(mintFunds);
    }

    function _burn(
        uint256 tokenId
    ) internal override(ERC721, ERC721URIStorage) {
        super._burn(tokenId);
    }

    function getRequiredValue(uint amount)public view returns(uint){
        return amount*(rafflePrice+mintPrice);
    }
}
