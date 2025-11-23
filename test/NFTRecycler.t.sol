// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {NFTRecycler} from "../src/NFTRecycler.sol";
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {ERC721Burnable} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

// Mock NFT com burn
contract MockNFTWithBurn is ERC721, ERC721Burnable, Ownable {
    uint256 private _nextTokenId;

    constructor(address initialOwner) ERC721("MockNFT", "MNFT") Ownable(initialOwner) {}

    function mint(address to) public returns (uint256) {
        uint256 tokenId = _nextTokenId++;
        _safeMint(to, tokenId);
        return tokenId;
    }

    function safeMint(address to, uint256 tokenId) public returns (uint256) {
        _safeMint(to, tokenId);
        return tokenId;
    }

    function getNextTokenId() public view returns (uint256) {
        return _nextTokenId;
    }
}

// Mock NFT sem burn
contract MockNFTWithoutBurn is ERC721 {
    uint256 private _nextTokenId;

    constructor() ERC721("MockNFTNoBurn", "MNFTNB") {}

    function mint(address to) public returns (uint256) {
        uint256 tokenId = _nextTokenId++;
        _mint(to, tokenId);
        return tokenId;
    }
}

// Mock NFT não-ERC721 (para testes de validação)
contract MockNonERC721 {
    function ownerOf(uint256) public pure returns (address) {
        return address(0);
    }
}

contract NFTRecyclerTest is Test {
    NFTRecycler public recycler;
    MockNFTWithBurn public nftWithBurn;
    MockNFTWithoutBurn public nftWithoutBurn;
    MockNonERC721 public nonERC721;

    address public owner;
    address public user1;
    address public user2;

    uint256 constant POINTS_PER_NFT = 100;
    uint256 constant UPDATED_POINTS = 200;

    event NFTContractAdded(address indexed nftContract, uint256 pointsPerNFT, uint256 timestamp);
    event NFTContractUpdated(address indexed nftContract, uint256 newPointsPerNFT, uint256 timestamp);
    event NFTContractRemoved(address indexed nftContract, uint256 timestamp);
    event NFTContractStatusChanged(address indexed nftContract, bool isActive, uint256 timestamp);
    event NFTRecycled(
        address indexed recycler,
        address indexed nftContract,
        uint256 indexed tokenId,
        uint256 pointsGenerated,
        uint256 timestamp
    );
    event RecyclingFailed(
        address indexed recycler, address indexed nftContract, uint256 tokenId, string reason, uint256 timestamp
    );

    function setUp() public {
        owner = address(this);
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");

        recycler = new NFTRecycler();
        nftWithBurn = new MockNFTWithBurn(owner);
        nftWithoutBurn = new MockNFTWithoutBurn();
        nonERC721 = new MockNonERC721();
    }

    // ============ Testes de Inicialização ============

    function test_InitialState() public view {
        assertEq(recycler.owner(), owner);
        assertEq(recycler.totalRecyclings(), 0);
        assertEq(recycler.totalPointsGenerated(), 0);
        assertEq(recycler.MAX_BATCH_SIZE(), 50);
        assertFalse(recycler.paused());
    }

    // ============ Testes de Adição de NFTs ============

    function test_AddAcceptedNFT() public {
        vm.expectEmit(true, false, false, true);
        emit NFTContractAdded(address(nftWithBurn), POINTS_PER_NFT, block.timestamp);

        recycler.addAcceptedNFT(address(nftWithBurn), POINTS_PER_NFT);

        NFTRecycler.NFTConfig memory config = recycler.getNFTConfig(address(nftWithBurn));
        assertEq(config.pointsPerNFT, POINTS_PER_NFT);
        assertTrue(config.isActive);
        assertEq(config.totalRecycled, 0);
        assertEq(config.dateAdded, block.timestamp);
    }

    function test_RevertWhen_AddingNFTWithZeroPoints() public {
        vm.expectRevert("Pontos devem ser maior que zero");
        recycler.addAcceptedNFT(address(nftWithBurn), 0);
    }

    function test_RevertWhen_AddingZeroAddress() public {
        vm.expectRevert("Endereco invalido");
        recycler.addAcceptedNFT(address(0), POINTS_PER_NFT);
    }

    function test_RevertWhen_AddingNonContract() public {
        vm.expectRevert("Deve ser um contrato");
        recycler.addAcceptedNFT(user1, POINTS_PER_NFT);
    }

    function test_RevertWhen_AddingNonERC721Contract() public {
        vm.expectRevert("Nao implementa ERC721");
        recycler.addAcceptedNFT(address(nonERC721), POINTS_PER_NFT);
    }

    function test_RevertWhen_AddingDuplicateNFT() public {
        recycler.addAcceptedNFT(address(nftWithBurn), POINTS_PER_NFT);

        vm.expectRevert("NFT ja cadastrado");
        recycler.addAcceptedNFT(address(nftWithBurn), POINTS_PER_NFT);
    }

    function test_RevertWhen_NonOwnerAddsNFT() public {
        vm.prank(user1);
        vm.expectRevert();
        recycler.addAcceptedNFT(address(nftWithBurn), POINTS_PER_NFT);
    }

    // ============ Testes de Atualização de NFTs ============

    function test_UpdateNFTPoints() public {
        recycler.addAcceptedNFT(address(nftWithBurn), POINTS_PER_NFT);

        vm.expectEmit(true, false, false, true);
        emit NFTContractUpdated(address(nftWithBurn), UPDATED_POINTS, block.timestamp);

        recycler.updateNFTPoints(address(nftWithBurn), UPDATED_POINTS);

        NFTRecycler.NFTConfig memory config = recycler.getNFTConfig(address(nftWithBurn));
        assertEq(config.pointsPerNFT, UPDATED_POINTS);
    }

    function test_RevertWhen_UpdatingNonRegisteredNFT() public {
        vm.expectRevert("NFT nao cadastrado");
        recycler.updateNFTPoints(address(nftWithBurn), UPDATED_POINTS);
    }

    function test_RevertWhen_UpdatingToZeroPoints() public {
        recycler.addAcceptedNFT(address(nftWithBurn), POINTS_PER_NFT);

        vm.expectRevert("Pontos devem ser maior que zero");
        recycler.updateNFTPoints(address(nftWithBurn), 0);
    }

    // ============ Testes de Status ============

    function test_SetNFTStatus() public {
        recycler.addAcceptedNFT(address(nftWithBurn), POINTS_PER_NFT);

        vm.expectEmit(true, false, false, true);
        emit NFTContractStatusChanged(address(nftWithBurn), false, block.timestamp);

        recycler.setNFTStatus(address(nftWithBurn), false);

        assertFalse(recycler.isNFTAccepted(address(nftWithBurn)));
    }

    function test_RevertWhen_SettingStatusOfNonRegisteredNFT() public {
        vm.expectRevert("NFT nao cadastrado");
        recycler.setNFTStatus(address(nftWithBurn), false);
    }

    // ============ Testes de Remoção ============

    function test_RemoveAcceptedNFT() public {
        recycler.addAcceptedNFT(address(nftWithBurn), POINTS_PER_NFT);

        vm.expectEmit(true, false, false, true);
        emit NFTContractRemoved(address(nftWithBurn), block.timestamp);

        recycler.removeAcceptedNFT(address(nftWithBurn));

        assertFalse(recycler.isNFTAccepted(address(nftWithBurn)));
    }

    // ============ Testes de Reciclagem com Burn ============

    function test_RecycleNFTWithBurn() public {
        recycler.addAcceptedNFT(address(nftWithBurn), POINTS_PER_NFT);

        uint256 tokenId = nftWithBurn.mint(user1);

        vm.startPrank(user1);
        nftWithBurn.approve(address(recycler), tokenId);

        vm.expectEmit(true, true, true, true);
        emit NFTRecycled(user1, address(nftWithBurn), tokenId, POINTS_PER_NFT, block.timestamp);

        uint256 points = recycler.recycleNFT(address(nftWithBurn), tokenId);
        vm.stopPrank();

        assertEq(points, POINTS_PER_NFT);
        assertEq(recycler.totalRecyclings(), 1);
        assertEq(recycler.totalPointsGenerated(), POINTS_PER_NFT);
        assertEq(recycler.userRecyclingCount(user1), 1);

        // Verifica que NFT foi queimado
        vm.expectRevert();
        nftWithBurn.ownerOf(tokenId);
    }

    function test_RevertWhen_RecyclingNFTNotOwned() public {
        recycler.addAcceptedNFT(address(nftWithBurn), POINTS_PER_NFT);

        uint256 tokenId = nftWithBurn.mint(user1);

        vm.prank(user2);
        vm.expectRevert("Nao e o dono do NFT");
        recycler.recycleNFT(address(nftWithBurn), tokenId);
    }

    function test_RevertWhen_RecyclingInactiveNFT() public {
        recycler.addAcceptedNFT(address(nftWithBurn), POINTS_PER_NFT);
        recycler.setNFTStatus(address(nftWithBurn), false);

        uint256 tokenId = nftWithBurn.mint(user1);

        vm.prank(user1);
        vm.expectRevert("NFT nao aceito");
        recycler.recycleNFT(address(nftWithBurn), tokenId);
    }

    function test_RevertWhen_RecyclingNFTWithoutBurnFunction() public {
        recycler.addAcceptedNFT(address(nftWithoutBurn), POINTS_PER_NFT);

        uint256 tokenId = nftWithoutBurn.mint(user1);

        vm.prank(user1);
        vm.expectRevert("Falha ao queimar NFT - use recycleNFTByTransfer");
        recycler.recycleNFT(address(nftWithoutBurn), tokenId);
    }

    // ============ Testes de Reciclagem por Transferência ============

    function test_RecycleNFTByTransfer() public {
        recycler.addAcceptedNFT(address(nftWithoutBurn), POINTS_PER_NFT);

        uint256 tokenId = nftWithoutBurn.mint(user1);

        vm.startPrank(user1);
        nftWithoutBurn.approve(address(recycler), tokenId);

        vm.expectEmit(true, true, true, true);
        emit NFTRecycled(user1, address(nftWithoutBurn), tokenId, POINTS_PER_NFT, block.timestamp);

        uint256 points = recycler.recycleNFTByTransfer(address(nftWithoutBurn), tokenId);
        vm.stopPrank();

        assertEq(points, POINTS_PER_NFT);
        assertEq(recycler.totalRecyclings(), 1);
        assertEq(nftWithoutBurn.ownerOf(tokenId), address(recycler));
    }

    // ============ Testes de Reciclagem em Lote ============

    function test_RecycleMultipleNFTs() public {
        recycler.addAcceptedNFT(address(nftWithBurn), POINTS_PER_NFT);
        recycler.addAcceptedNFT(address(nftWithoutBurn), POINTS_PER_NFT);

        uint256 token1 = nftWithBurn.mint(user1);
        uint256 token2 = nftWithoutBurn.mint(user1);

        address[] memory contracts = new address[](2);
        contracts[0] = address(nftWithBurn);
        contracts[1] = address(nftWithoutBurn);

        uint256[] memory tokenIds = new uint256[](2);
        tokenIds[0] = token1;
        tokenIds[1] = token2;

        bool[] memory useBurn = new bool[](2);
        useBurn[0] = true;
        useBurn[1] = false;

        vm.startPrank(user1);
        nftWithBurn.approve(address(recycler), token1);
        nftWithoutBurn.approve(address(recycler), token2);

        uint256 totalPoints = recycler.recycleMultipleNFTs(contracts, tokenIds, useBurn);
        vm.stopPrank();

        assertEq(totalPoints, POINTS_PER_NFT * 2);
        assertEq(recycler.totalRecyclings(), 2);
    }

    function test_RecycleMultipleNFTs_WithPartialFailure() public {
        recycler.addAcceptedNFT(address(nftWithBurn), POINTS_PER_NFT);

        uint256 token1 = 123;
        nftWithBurn.safeMint(user1, token1);
        uint256 token2 = 345;
        nftWithBurn.safeMint(user2, token2); // Não pertence a user1

        address[] memory contracts = new address[](2);
        contracts[0] = address(nftWithBurn);
        contracts[1] = address(nftWithBurn);

        uint256[] memory tokenIds = new uint256[](2);
        tokenIds[0] = token1;
        tokenIds[1] = token2;

        bool[] memory useBurn = new bool[](2);
        useBurn[0] = true;
        useBurn[1] = true;

        vm.startPrank(user1);
        nftWithBurn.approve(address(recycler), token1);

        vm.expectEmit(true, true, false, false);
        emit RecyclingFailed(user1, address(nftWithBurn), token2, "Nao e o dono", block.timestamp);

        uint256 totalPoints = recycler.recycleMultipleNFTs(contracts, tokenIds, useBurn);
        vm.stopPrank();

        assertEq(totalPoints, POINTS_PER_NFT); // Apenas 1 sucesso
        assertEq(recycler.totalRecyclings(), 1);
    }

    function test_RevertWhen_RecyclingMultipleWithMismatchedArrays() public {
        address[] memory contracts = new address[](2);
        uint256[] memory tokenIds = new uint256[](3);
        bool[] memory useBurn = new bool[](2);

        vm.prank(user1);
        vm.expectRevert("Arrays com tamanhos diferentes");
        recycler.recycleMultipleNFTs(contracts, tokenIds, useBurn);
    }

    function test_RevertWhen_RecyclingMultipleExceedsBatchSize() public {
        address[] memory contracts = new address[](51);
        uint256[] memory tokenIds = new uint256[](51);
        bool[] memory useBurn = new bool[](51);

        vm.prank(user1);
        vm.expectRevert("Limite de lote excedido");
        recycler.recycleMultipleNFTs(contracts, tokenIds, useBurn);
    }

    function test_RevertWhen_RecyclingMultipleWithEmptyArray() public {
        address[] memory contracts = new address[](0);
        uint256[] memory tokenIds = new uint256[](0);
        bool[] memory useBurn = new bool[](0);

        vm.prank(user1);
        vm.expectRevert("Array vazio");
        recycler.recycleMultipleNFTs(contracts, tokenIds, useBurn);
    }

    // ============ Testes de Consulta ============

    function test_GetUserRecyclingHistory() public {
        recycler.addAcceptedNFT(address(nftWithBurn), POINTS_PER_NFT);

        uint256 token1 = nftWithBurn.mint(user1);
        uint256 token2 = nftWithBurn.mint(user1);

        vm.startPrank(user1);
        nftWithBurn.approve(address(recycler), token1);
        nftWithBurn.approve(address(recycler), token2);

        recycler.recycleNFT(address(nftWithBurn), token1);
        recycler.recycleNFT(address(nftWithBurn), token2);
        vm.stopPrank();

        NFTRecycler.RecyclingRecord[] memory history = recycler.getUserRecyclingHistory(user1);

        assertEq(history.length, 2);
        assertEq(history[0].recycler, user1);
        assertEq(history[0].tokenId, token1);
        assertEq(history[1].tokenId, token2);
    }

    function test_GetNFTContractHistory() public {
        recycler.addAcceptedNFT(address(nftWithBurn), POINTS_PER_NFT);

        uint256 token1 = nftWithBurn.getNextTokenId() + 12;
        nftWithBurn.safeMint(address(user1), token1);
        uint256 token2 = nftWithBurn.getNextTokenId() + 22;
        nftWithBurn.safeMint(user2, token2);

        vm.startPrank(user1);
        nftWithBurn.approve(address(recycler), token1);
        //console.log("token1:", token1);
        assertEq(nftWithBurn.ownerOf(token1), user1);
        console.log("owner of token1:", nftWithBurn.ownerOf(token1));
        console.log("sender:", msg.sender);

        recycler.recycleNFT(address(nftWithBurn), token1);
        vm.stopPrank();

        vm.startPrank(user2);
        nftWithBurn.approve(address(recycler), token2);
        recycler.recycleNFT(address(nftWithBurn), token2);
        vm.stopPrank();

        NFTRecycler.RecyclingRecord[] memory history = recycler.getNFTContractHistory(address(nftWithBurn));

        assertEq(history.length, 2);
        assertEq(history[0].nftContract, address(nftWithBurn));
        assertEq(history[1].nftContract, address(nftWithBurn));
    }

    function test_CalculatePoints() public {
        recycler.addAcceptedNFT(address(nftWithBurn), POINTS_PER_NFT);

        uint256 points = recycler.calculatePoints(address(nftWithBurn), 5);
        assertEq(points, POINTS_PER_NFT * 5);
    }

    function test_CanRecycle() public {
        recycler.addAcceptedNFT(address(nftWithBurn), POINTS_PER_NFT);
        uint256 tokenId = nftWithBurn.mint(user1);

        (bool can, string memory reason) = recycler.canRecycle(user1, address(nftWithBurn), tokenId);

        assertTrue(can);
        assertEq(reason, "Pode reciclar");
    }

    function test_CanRecycle_NotOwner() public {
        recycler.addAcceptedNFT(address(nftWithBurn), POINTS_PER_NFT);
        uint256 tokenId = nftWithBurn.mint(user1);

        (bool can, string memory reason) = recycler.canRecycle(user2, address(nftWithBurn), tokenId);

        assertFalse(can);
        assertEq(reason, "Nao e o dono do NFT");
    }

    function test_CanRecycle_NotAccepted() public {
        uint256 tokenId = nftWithBurn.mint(user1);

        (bool can, string memory reason) = recycler.canRecycle(user1, address(nftWithBurn), tokenId);

        assertFalse(can);
        assertEq(reason, "NFT nao aceito");
    }

    function test_GetStats() public {
        recycler.addAcceptedNFT(address(nftWithBurn), POINTS_PER_NFT);

        uint256 tokenId = nftWithBurn.mint(user1);

        vm.startPrank(user1);
        nftWithBurn.approve(address(recycler), tokenId);
        recycler.recycleNFT(address(nftWithBurn), tokenId);
        vm.stopPrank();

        (uint256 totalRecyclings, uint256 totalPoints, uint256 activeContracts) = recycler.getStats();

        assertEq(totalRecyclings, 1);
        assertEq(totalPoints, POINTS_PER_NFT);
        assertEq(activeContracts, 0); // Nota no código
    }

    function test_GetHistorySize() public {
        recycler.addAcceptedNFT(address(nftWithBurn), POINTS_PER_NFT);

        uint256 token1 = nftWithBurn.mint(user1);
        uint256 token2 = nftWithBurn.mint(user1);

        vm.startPrank(user1);
        nftWithBurn.approve(address(recycler), token1);
        nftWithBurn.approve(address(recycler), token2);

        recycler.recycleNFT(address(nftWithBurn), token1);
        recycler.recycleNFT(address(nftWithBurn), token2);
        vm.stopPrank();

        assertEq(recycler.getHistorySize(), 2);
    }

    // ============ Testes de Pausa ============

    function test_PauseUnpause() public {
        recycler.pause();
        assertTrue(recycler.paused());

        recycler.unpause();
        assertFalse(recycler.paused());
    }

    function test_RevertWhen_RecyclingWhilePaused() public {
        recycler.addAcceptedNFT(address(nftWithBurn), POINTS_PER_NFT);
        recycler.pause();

        uint256 tokenId = nftWithBurn.mint(user1);

        vm.prank(user1);
        vm.expectRevert();
        recycler.recycleNFT(address(nftWithBurn), tokenId);
    }

    function test_RevertWhen_NonOwnerPauses() public {
        vm.prank(user1);
        vm.expectRevert();
        recycler.pause();
    }

    // ============ Testes de ERC721Receiver ============

    function test_OnERC721Received() public view {
        bytes4 selector = recycler.onERC721Received(address(0), address(0), 0, "");
        assertEq(selector, recycler.onERC721Received.selector);
    }

    // ============ Testes Fuzz ============

    function testFuzz_AddAcceptedNFT(uint256 points) public {
        vm.assume(points > 0 && points < recycler.MAX_POINTS_PER_NFT());

        recycler.addAcceptedNFT(address(nftWithBurn), points);

        NFTRecycler.NFTConfig memory config = recycler.getNFTConfig(address(nftWithBurn));
        assertEq(config.pointsPerNFT, points);
    }

    function testFuzz_RecycleNFT(uint256 points) public {
        vm.assume(points > 0 && points < recycler.MAX_POINTS_PER_NFT());

        recycler.addAcceptedNFT(address(nftWithBurn), points);

        uint256 tokenId = nftWithBurn.mint(user1);

        vm.startPrank(user1);
        nftWithBurn.approve(address(recycler), tokenId);
        uint256 generatedPoints = recycler.recycleNFT(address(nftWithBurn), tokenId);
        vm.stopPrank();

        assertEq(generatedPoints, points);
        assertEq(recycler.totalPointsGenerated(), points);
    }

    function testFuzz_CalculatePoints(uint256 quantity, uint256 pointsPerNFT) public pure {
        vm.assume(quantity > 0 && quantity < 1000);
        vm.assume(pointsPerNFT > 0 && pointsPerNFT < type(uint128).max);
        vm.assume(quantity * pointsPerNFT < type(uint256).max); // Evitar overflow

        uint256 expected = quantity * pointsPerNFT;
        assertTrue(expected >= quantity);
        assertTrue(expected >= pointsPerNFT);
    }

    // ============ Testes de Invariantes ============

    function invariant_TotalPointsMatchesHistory() public view {
        // Total de pontos deve ser igual à soma do histórico
        uint256 historySum = 0;
        uint256 historySize = recycler.getHistorySize();

        for (uint256 i = 0; i < historySize; i++) {
            (,,, uint256 points,,) = recycler.recyclingHistory(i);
            historySum += points;
        }

        assertEq(recycler.totalPointsGenerated(), historySum);
    }

    function invariant_TotalRecyclingsMatchesHistoryLength() public view {
        assertEq(recycler.totalRecyclings(), recycler.getHistorySize());
    }
}
