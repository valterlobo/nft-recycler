// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console2} from "forge-std/Script.sol";
import {NFTRecycler} from "../src/NFTRecycler.sol";

/**
 * @title DeployNFTRecycler
 * @notice Script de deploy do contrato NFTRecycler usando Foundry
 * @dev Execute com: forge script script/Deploy.s.sol:DeployNFTRecycler --rpc-url <RPC_URL> --broadcast --verify
 */
contract DeployNFTRecycler is Script {
    // ============ Variáveis de Configuração ============

    // Endereços de NFTs de exemplo (ajuste para sua rede)
    address constant BAYC_MAINNET = 0xBC4CA0EdA7647A8aB7C2061c2E118A18a936f13D;
    address constant AZUKI_MAINNET = 0xED5AF388653567Af2F388E6224dC7C4b3241C544;

    // Pontos padrão por NFT
    uint256 constant DEFAULT_POINTS_BAYC = 1000;
    uint256 constant DEFAULT_POINTS_AZUKI = 800;

    // ============ Função Principal de Deploy ============

    function run() external returns (NFTRecycler recycler) {
        // Carrega private key do ambiente
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console2.log("===========================================");
        console2.log("Deploying NFTRecycler Contract");
        console2.log("===========================================");
        console2.log("Deployer:", deployer);
        console2.log("Chain ID:", block.chainid);
        console2.log("===========================================");

        // Inicia broadcast das transações
        vm.startBroadcast(deployerPrivateKey);

        // 1. Deploy do contrato principal
        recycler = new NFTRecycler();
        console2.log("NFTRecycler deployed at:", address(recycler));

        // 2. Configuração inicial (opcional - apenas em testnet/mainnet)
        if (shouldConfigureNFTs()) {
            configureInitialNFTs(recycler);
        }

        vm.stopBroadcast();

        // 3. Verificação pós-deploy
        verifyDeployment(recycler);

        console2.log("===========================================");
        console2.log("Deployment completed successfully!");
        console2.log("===========================================");

        return recycler;
    }

    // ============ Funções de Configuração ============

    /**
     * @notice Configura NFTs iniciais aceitos (apenas para mainnet/testnet)
     */
    function configureInitialNFTs(NFTRecycler recycler) internal {
        console2.log("\nConfiguring initial NFT contracts...");

        // Verifica se estamos na mainnet
        if (block.chainid == 1) {
            // Mainnet Ethereum
            configureMainnetNFTs(recycler);
        } else if (block.chainid == 11155111) {
            // Sepolia Testnet
            configureSepoliaTestnet(recycler);
        } else if (block.chainid == 80001) {
            // Mumbai Testnet
            configureMumbaiTestnet(recycler);
        } else {
            console2.log("Network not configured for automatic NFT setup");
        }
    }

    /**
     * @notice Configuração para Mainnet Ethereum
     */
    function configureMainnetNFTs(NFTRecycler recycler) internal {
        console2.log("Configuring Mainnet NFTs...");

        try recycler.addAcceptedNFT(BAYC_MAINNET, DEFAULT_POINTS_BAYC) {
            console2.log("Added BAYC:", BAYC_MAINNET);
        } catch {
            console2.log("Warning: Could not add BAYC (may not implement ERC721)");
        }

        try recycler.addAcceptedNFT(AZUKI_MAINNET, DEFAULT_POINTS_AZUKI) {
            console2.log("Added Azuki:", AZUKI_MAINNET);
        } catch {
            console2.log("Warning: Could not add Azuki (may not implement ERC721)");
        }
    }

    /**
     * @notice Configuração para Sepolia Testnet
     */
    function configureSepoliaTestnet(NFTRecycler recycler) internal {
        console2.log("Sepolia testnet - No default NFTs configured");
        console2.log("Use addAcceptedNFT() to add test NFT contracts");
    }

    /**
     * @notice Configuração para Mumbai Testnet
     */
    function configureMumbaiTestnet(NFTRecycler recycler) internal {
        console2.log("Mumbai testnet - No default NFTs configured");
        console2.log("Use addAcceptedNFT() to add test NFT contracts");
    }

    // ============ Funções Auxiliares ============

    /**
     * @notice Verifica se deve configurar NFTs automaticamente
     */
    function shouldConfigureNFTs() internal view returns (bool) {
        // Desabilita configuração automática em redes locais
        if (block.chainid == 31337 || block.chainid == 1337) {
            return false;
        }

        // Tenta ler variável de ambiente
        try vm.envBool("CONFIGURE_NFTS") returns (bool shouldConfigure) {
            return shouldConfigure;
        } catch {
            return false; // Default: não configurar
        }
    }

    /**
     * @notice Verifica o deployment executando algumas leituras
     */
    function verifyDeployment(NFTRecycler recycler) internal view {
        console2.log("\nVerifying deployment...");

        // Verifica owner
        address owner = recycler.owner();
        console2.log("Contract owner:", owner);
        require(owner == vm.addr(vm.envUint("PRIVATE_KEY")), "Owner mismatch");

        // Verifica estado inicial
        (uint256 totalRecyclings, uint256 totalPoints,) = recycler.getStats();
        console2.log("Initial total recyclings:", totalRecyclings);
        console2.log("Initial total points:", totalPoints);
        require(totalRecyclings == 0, "Invalid initial state");
        require(totalPoints == 0, "Invalid initial state");

        // Verifica constantes
        uint256 maxBatch = recycler.MAX_BATCH_SIZE();
        console2.log("Max batch size:", maxBatch);
        require(maxBatch == 50, "Invalid MAX_BATCH_SIZE");

        console2.log("Verification passed!");
    }
}

/**
 * @title DeployWithMockNFTs
 * @notice Script para deploy com NFTs de teste (para desenvolvimento local)
 */
contract DeployWithMockNFTs is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        console2.log("===========================================");
        console2.log("Deploying NFTRecycler with Mock NFTs");
        console2.log("===========================================");

        vm.startBroadcast(deployerPrivateKey);

        // 1. Deploy do recycler
        NFTRecycler recycler = new NFTRecycler();
        console2.log("NFTRecycler deployed at:", address(recycler));

        // 2. Deploy de NFTs mock para teste
        MockERC721 mockNFT1 = new MockERC721("Mock Collection 1", "MOCK1");
        MockERC721 mockNFT2 = new MockERC721("Mock Collection 2", "MOCK2");

        console2.log("Mock NFT 1 deployed at:", address(mockNFT1));
        console2.log("Mock NFT 2 deployed at:", address(mockNFT2));

        // 3. Adiciona NFTs mock ao recycler
        recycler.addAcceptedNFT(address(mockNFT1), 100);
        recycler.addAcceptedNFT(address(mockNFT2), 150);

        console2.log("Mock NFTs configured");

        // 4. Mint alguns NFTs para teste
        address deployer = vm.addr(deployerPrivateKey);
        mockNFT1.mint(deployer, 1);
        mockNFT1.mint(deployer, 2);
        mockNFT2.mint(deployer, 1);

        console2.log("Minted test NFTs to deployer");

        vm.stopBroadcast();

        console2.log("===========================================");
        console2.log("Deployment Summary:");
        console2.log("NFTRecycler:", address(recycler));
        console2.log("Mock NFT 1:", address(mockNFT1));
        console2.log("Mock NFT 2:", address(mockNFT2));
        console2.log("===========================================");
    }
}

/**
 * @title MockERC721
 * @notice NFT mock simples para testes
 */
contract MockERC721 {
    string public name;
    string public symbol;

    mapping(uint256 => address) private _owners;
    mapping(address => uint256) private _balances;
    mapping(uint256 => address) private _tokenApprovals;
    mapping(address => mapping(address => bool)) private _operatorApprovals;

    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);
    event Approval(address indexed owner, address indexed approved, uint256 indexed tokenId);
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);

    constructor(string memory _name, string memory _symbol) {
        name = _name;
        symbol = _symbol;
    }

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == 0x80ac58cd || interfaceId == 0x01ffc9a7;
    }

    function ownerOf(uint256 tokenId) public view returns (address) {
        address owner = _owners[tokenId];
        require(owner != address(0), "Token does not exist");
        return owner;
    }

    function balanceOf(address owner) external view returns (uint256) {
        require(owner != address(0), "Invalid address");
        return _balances[owner];
    }

    function mint(address to, uint256 tokenId) external {
        require(to != address(0), "Invalid address");
        require(_owners[tokenId] == address(0), "Token already exists");

        _balances[to] += 1;
        _owners[tokenId] = to;

        emit Transfer(address(0), to, tokenId);
    }

    function burn(uint256 tokenId) external {
        address owner = ownerOf(tokenId);
        require(msg.sender == owner || _tokenApprovals[tokenId] == msg.sender, "Not authorized");

        _balances[owner] -= 1;
        delete _owners[tokenId];
        delete _tokenApprovals[tokenId];

        emit Transfer(owner, address(0), tokenId);
    }

    function approve(address to, uint256 tokenId) external {
        address owner = ownerOf(tokenId);
        require(msg.sender == owner, "Not owner");

        _tokenApprovals[tokenId] = to;
        emit Approval(owner, to, tokenId);
    }

    function getApproved(uint256 tokenId) external view returns (address) {
        require(_owners[tokenId] != address(0), "Token does not exist");
        return _tokenApprovals[tokenId];
    }

    function setApprovalForAll(address operator, bool approved) external {
        _operatorApprovals[msg.sender][operator] = approved;
        emit ApprovalForAll(msg.sender, operator, approved);
    }

    function isApprovedForAll(address owner, address operator) external view returns (bool) {
        return _operatorApprovals[owner][operator];
    }

    function safeTransferFrom(address from, address to, uint256 tokenId) external {
        transferFrom(from, to, tokenId);
    }

    function transferFrom(address from, address to, uint256 tokenId) public {
        require(to != address(0), "Invalid address");
        address owner = ownerOf(tokenId);
        require(from == owner, "Not owner");
        require(
            msg.sender == owner || _tokenApprovals[tokenId] == msg.sender || _operatorApprovals[owner][msg.sender],
            "Not authorized"
        );

        delete _tokenApprovals[tokenId];

        _balances[from] -= 1;
        _balances[to] += 1;
        _owners[tokenId] = to;

        emit Transfer(from, to, tokenId);
    }
}
