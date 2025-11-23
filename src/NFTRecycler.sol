// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {ERC165Checker} from "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";

/**
 * @title NFTRecycler - 1.1
 * @notice Contrato para reciclagem de NFTs gerando pontos baseados em pegada de carbono
 * @dev Implementa sistema de reciclagem com burn ou transferência de NFTs
 */
contract NFTRecycler is Ownable, Pausable, ReentrancyGuard {
    using ERC165Checker for address;

    // ============ Estruturas ============

    struct NFTConfig {
        uint256 pointsPerNFT;
        bool isActive;
        uint256 totalRecycled;
        uint256 dateAdded;
    }

    struct RecyclingRecord {
        address recycler;
        address nftContract;
        uint256 tokenId;
        uint256 pointsGenerated;
        uint256 timestamp;
        uint256 blockNumber;
    }

    // ============ Variáveis de Estado ============

    mapping(address => NFTConfig) public acceptedNFTs;
    RecyclingRecord[] public recyclingHistory;
    mapping(address => uint256) public userRecyclingCount;

    // NOVO: Mapeamento para histórico eficiente
    mapping(address => uint256[]) private userRecyclingIndices;

    uint256 public totalRecyclings;
    uint256 public totalPointsGenerated;
    uint256 public constant MAX_BATCH_SIZE = 50;

    // NOVO: Limite máximo de pontos por NFT
    uint256 public constant MAX_POINTS_PER_NFT = 1_000_000;

    bytes4 private constant INTERFACE_ID_ERC721 = 0x80ac58cd;

    // ============ Eventos ============

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

    // NOVO: Evento de resgate
    event EmergencyRescue(address indexed nftContract, uint256 tokenId, address to);

    // ============ Modificadores ============

    modifier validNFTContract(address _nftContract) {
        require(_nftContract != address(0), "Endereco invalido");
        require(_isContract(_nftContract), "Deve ser um contrato");
        _;
    }

    modifier nftIsAccepted(address _nftContract) {
        require(acceptedNFTs[_nftContract].isActive, "NFT nao aceito");
        _;
    }

    // ============ Constructor ============

    constructor() Ownable(msg.sender) {}

    // ============ Funções Administrativas ============

    function addAcceptedNFT(address _nftContract, uint256 _pointsPerNFT)
        external
        onlyOwner
        validNFTContract(_nftContract)
    {
        require(_pointsPerNFT > 0, "Pontos devem ser maior que zero");
        require(_pointsPerNFT <= MAX_POINTS_PER_NFT, "Pontos excedem limite maximo"); // NOVO
        require(!acceptedNFTs[_nftContract].isActive, "NFT ja cadastrado");
        require(_supportsERC721(_nftContract), "Nao implementa ERC721");

        acceptedNFTs[_nftContract] =
            NFTConfig({pointsPerNFT: _pointsPerNFT, isActive: true, totalRecycled: 0, dateAdded: block.timestamp});

        emit NFTContractAdded(_nftContract, _pointsPerNFT, block.timestamp);
    }

    function updateNFTPoints(address _nftContract, uint256 _newPointsPerNFT) external onlyOwner {
        require(acceptedNFTs[_nftContract].dateAdded > 0, "NFT nao cadastrado");
        require(_newPointsPerNFT > 0, "Pontos devem ser maior que zero");
        require(_newPointsPerNFT <= MAX_POINTS_PER_NFT, "Pontos excedem limite maximo"); // NOVO

        acceptedNFTs[_nftContract].pointsPerNFT = _newPointsPerNFT;

        emit NFTContractUpdated(_nftContract, _newPointsPerNFT, block.timestamp);
    }

    function setNFTStatus(address _nftContract, bool _isActive) external onlyOwner {
        require(acceptedNFTs[_nftContract].dateAdded > 0, "NFT nao cadastrado");
        acceptedNFTs[_nftContract].isActive = _isActive;
        emit NFTContractStatusChanged(_nftContract, _isActive, block.timestamp);
    }

    function removeAcceptedNFT(address _nftContract) external onlyOwner {
        require(acceptedNFTs[_nftContract].dateAdded > 0, "NFT nao cadastrado");
        acceptedNFTs[_nftContract].isActive = false;
        emit NFTContractRemoved(_nftContract, block.timestamp);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    // NOVO: Função de resgate de emergência
    /**
     * @notice Resgata NFTs presos no contrato em caso de emergência
     * @param _nftContract Endereço do contrato NFT
     * @param _tokenId ID do token
     */
    function emergencyRescueNFT(address _nftContract, uint256 _tokenId) external onlyOwner {
        IERC721(_nftContract).safeTransferFrom(address(this), owner(), _tokenId);
        emit EmergencyRescue(_nftContract, _tokenId, owner());
    }

    // ============ Funções de Reciclagem ============

    /**
     * @notice Recicla um NFT através de queima (burn)
     */
    function recycleNFT(address _nftContract, uint256 _tokenId)
        external
        whenNotPaused
        nonReentrant // NOVO
        nftIsAccepted(_nftContract)
        returns (uint256 pointsGenerated)
    {
        IERC721 nft = IERC721(_nftContract);

        // Verifica propriedade
        require(nft.ownerOf(_tokenId) == msg.sender, "Nao e o dono do NFT");

        // Obtém pontos ANTES da chamada externa (CEI pattern)
        pointsGenerated = acceptedNFTs[_nftContract].pointsPerNFT;

        // Tenta fazer burn
        (bool success,) = _nftContract.call(abi.encodeWithSignature("burn(uint256)", _tokenId));
        require(success, "Falha ao queimar NFT - use recycleNFTByTransfer");

        // NOVO: Verifica que o burn realmente ocorreu
        try nft.ownerOf(_tokenId) returns (address) {
            revert("NFT nao foi queimado - use recycleNFTByTransfer");
        } catch {
            // NFT foi queimado com sucesso (ownerOf reverte)
        }

        // Cria registro (estado atualizado após chamada externa)
        _createRecyclingRecord(msg.sender, _nftContract, _tokenId, pointsGenerated);

        emit NFTRecycled(msg.sender, _nftContract, _tokenId, pointsGenerated, block.timestamp);

        return pointsGenerated;
    }

    /**
     * @notice Recicla um NFT através de transferência
     */
    function recycleNFTByTransfer(address _nftContract, uint256 _tokenId)
        external
        whenNotPaused
        nonReentrant // NOVO
        nftIsAccepted(_nftContract)
        returns (uint256 pointsGenerated)
    {
        IERC721 nft = IERC721(_nftContract);

        // Verifica propriedade
        require(nft.ownerOf(_tokenId) == msg.sender, "Nao e o dono do NFT");

        // Obtém pontos ANTES da transferência
        pointsGenerated = acceptedNFTs[_nftContract].pointsPerNFT;

        // Transfere NFT para este contrato
        nft.safeTransferFrom(msg.sender, address(this), _tokenId);

        // Cria registro
        _createRecyclingRecord(msg.sender, _nftContract, _tokenId, pointsGenerated);

        emit NFTRecycled(msg.sender, _nftContract, _tokenId, pointsGenerated, block.timestamp);

        return pointsGenerated;
    }

    /**
     * @notice Recicla múltiplos NFTs em uma única transação
     */
    function recycleMultipleNFTs(
        address[] calldata _nftContracts,
        uint256[] calldata _tokenIds,
        bool[] calldata _useBurn
    ) external whenNotPaused nonReentrant returns (uint256 totalPoints) {
        // NOVO: nonReentrant
        require(
            _nftContracts.length == _tokenIds.length && _tokenIds.length == _useBurn.length,
            "Arrays com tamanhos diferentes"
        );
        require(_nftContracts.length <= MAX_BATCH_SIZE, "Limite de lote excedido");
        require(_nftContracts.length > 0, "Array vazio");

        for (uint256 i = 0; i < _nftContracts.length; i++) {
            try this.recycleSingle(_nftContracts[i], _tokenIds[i], _useBurn[i], msg.sender) returns (uint256 points) {
                totalPoints += points;
            } catch Error(string memory reason) {
                emit RecyclingFailed(msg.sender, _nftContracts[i], _tokenIds[i], reason, block.timestamp);
            } catch {
                emit RecyclingFailed(msg.sender, _nftContracts[i], _tokenIds[i], "Erro desconhecido", block.timestamp);
            }
        }

        return totalPoints;
    }

    /**
     * @notice Função auxiliar para reciclagem em lote
     */
    function recycleSingle(address _nftContract, uint256 _tokenId, bool _useBurn, address _originalCaller)
        external
        whenNotPaused // NOVO
        returns (uint256)
    {
        require(msg.sender == address(this), "Apenas chamada interna");
        require(acceptedNFTs[_nftContract].isActive, "NFT nao aceito");

        IERC721 nft = IERC721(_nftContract);
        require(nft.ownerOf(_tokenId) == _originalCaller, "Nao e o dono");

        uint256 points = acceptedNFTs[_nftContract].pointsPerNFT;

        if (_useBurn) {
            (bool success,) = _nftContract.call(abi.encodeWithSignature("burn(uint256)", _tokenId));
            require(success, "Falha ao queimar");

            // NOVO: Verifica burn real
            try nft.ownerOf(_tokenId) returns (address) {
                revert("NFT nao foi queimado");
            } catch {
                // Burn bem-sucedido
            }
        } else {
            nft.safeTransferFrom(_originalCaller, address(this), _tokenId);
        }

        _createRecyclingRecord(_originalCaller, _nftContract, _tokenId, points);
        emit NFTRecycled(_originalCaller, _nftContract, _tokenId, points, block.timestamp);

        return points;
    }

    // ============ Funções de Consulta ============

    function getNFTConfig(address _nftContract) external view returns (NFTConfig memory) {
        return acceptedNFTs[_nftContract];
    }

    function isNFTAccepted(address _nftContract) external view returns (bool) {
        return acceptedNFTs[_nftContract].isActive;
    }

    function calculatePoints(address _nftContract, uint256 _quantity) external view returns (uint256) {
        return acceptedNFTs[_nftContract].pointsPerNFT * _quantity;
    }

    /**
     * @notice Retorna histórico de reciclagens de um usuário
     * @param _user Endereço do usuário
     * @return records Array de registros
     */
    function getUserRecyclingHistory(address _user) external view returns (RecyclingRecord[] memory) {
        uint256 count = 0;

        // Conta quantos registros o usuário tem
        uint256 max = recyclingHistory.length;
        for (uint256 i = 0; i < max; i++) {
            if (recyclingHistory[i].recycler == _user) {
                count++;
            }
        }

        // Cria array com tamanho exato
        RecyclingRecord[] memory userRecords = new RecyclingRecord[](count);
        uint256 index = 0;

        // Preenche array
        uint256 size = recyclingHistory.length;
        for (uint256 i = 0; i < size; i++) {
            if (recyclingHistory[i].recycler == _user) {
                userRecords[index] = recyclingHistory[i];
                index++;
            }
        }

        return userRecords;
    }

    /**
     * @notice Retorna histórico de um contrato NFT específico
     * @param _nftContract Endereço do contrato
     * @return records Array de registros
     */
    function getNFTContractHistory(address _nftContract) external view returns (RecyclingRecord[] memory) {
        uint256 count = 0;

        uint256 size = recyclingHistory.length;
        for (uint256 i = 0; i < size; i++) {
            if (recyclingHistory[i].nftContract == _nftContract) {
                count++;
            }
        }

        RecyclingRecord[] memory contractRecords = new RecyclingRecord[](count);
        uint256 index = 0;

        for (uint256 i = 0; i < size; i++) {
            if (recyclingHistory[i].nftContract == _nftContract) {
                contractRecords[index] = recyclingHistory[i];
                index++;
            }
        }

        return contractRecords;
    }

    function getStats()
        external
        view
        returns (uint256 _totalRecyclings, uint256 _totalPoints, uint256 activeContracts)
    {
        return (totalRecyclings, totalPointsGenerated, 0);
    }

    function canRecycle(address _user, address _nftContract, uint256 _tokenId)
        external
        view
        returns (bool resultCanRecycle, string memory reason)
    {
        if (!acceptedNFTs[_nftContract].isActive) {
            return (false, "NFT nao aceito");
        }

        IERC721 nft = IERC721(_nftContract);

        try nft.ownerOf(_tokenId) returns (address owner) {
            if (owner != _user) {
                return (false, "Nao e o dono do NFT");
            }
        } catch {
            return (false, "NFT nao existe");
        }

        return (true, "Pode reciclar");
    }

    function getHistorySize() external view returns (uint256) {
        return recyclingHistory.length;
    }

    // ============ Funções Internas ============

    function _isContract(address _addr) internal view returns (bool) {
        uint256 size;
        assembly {
            size := extcodesize(_addr)
        }
        return size > 0;
    }

    function _supportsERC721(address _nftContract) internal view returns (bool) {
        try IERC721(_nftContract).supportsInterface(INTERFACE_ID_ERC721) returns (bool supported) {
            return supported;
        } catch {
            return false;
        }
    }

    /**
     * @notice Cria e armazena registro de reciclagem
     */
    function _createRecyclingRecord(address _recycler, address _nftContract, uint256 _tokenId, uint256 _points)
        internal
    {
        uint256 newIndex = recyclingHistory.length;

        recyclingHistory.push(
            RecyclingRecord({
                recycler: _recycler,
                nftContract: _nftContract,
                tokenId: _tokenId,
                pointsGenerated: _points,
                timestamp: block.timestamp,
                blockNumber: block.number
            })
        );

        // NOVO: Adiciona índice ao mapeamento do usuário
        userRecyclingIndices[_recycler].push(newIndex);

        // Atualiza contadores
        userRecyclingCount[_recycler]++;
        acceptedNFTs[_nftContract].totalRecycled++;
        totalRecyclings++;
        totalPointsGenerated += _points;
    }

    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return this.onERC721Received.selector;
    }
}
