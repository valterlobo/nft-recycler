// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {ERC165Checker} from "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";

/**
 * @title NFTRecycler
 * @notice Contrato para reciclagem de NFTs gerando pontos baseados em pegada de carbono
 * @dev Implementa sistema de reciclagem com burn ou transferência de NFTs
 */
contract NFTRecycler is Ownable, Pausable {
    using ERC165Checker for address;

    // ============ Estruturas ============

    /// @notice Configuração de um contrato NFT aceito
    struct NFTConfig {
        uint256 pointsPerNFT; // Pontos fixos gerados por NFT
        bool isActive; // Se o contrato está ativo
        uint256 totalRecycled; // Total de NFTs reciclados
        uint256 dateAdded; // Timestamp de inclusão
    }

    /// @notice Registro de uma reciclagem
    struct RecyclingRecord {
        address recycler; // Quem reciclou
        address nftContract; // Contrato do NFT
        uint256 tokenId; // ID do token
        uint256 pointsGenerated; // Pontos gerados
        uint256 timestamp; // Quando ocorreu
        uint256 blockNumber; // Bloco da transação
    }

    // ============ Variáveis de Estado ============

    /// @notice Mapeamento de contratos NFT aceitos
    mapping(address => NFTConfig) public acceptedNFTs;

    /// @notice Histórico completo de reciclagens
    RecyclingRecord[] public recyclingHistory;

    /// @notice Contador de reciclagens por usuário
    mapping(address => uint256) public userRecyclingCount;

    /// @notice Total de reciclagens realizadas
    uint256 public totalRecyclings;

    /// @notice Total de pontos gerados no sistema
    uint256 public totalPointsGenerated;

    /// @notice Limite de NFTs por transação em lote
    uint256 public constant MAX_BATCH_SIZE = 50;

    /// @notice Interface ID do ERC721
    bytes4 private constant INTERFACE_ID_ERC721 = 0x80ac58cd;

    // ============ Eventos ============

    /// @notice Emitido quando um contrato NFT é adicionado
    event NFTContractAdded(address indexed nftContract, uint256 pointsPerNFT, uint256 timestamp);

    /// @notice Emitido quando pontos são atualizados
    event NFTContractUpdated(address indexed nftContract, uint256 newPointsPerNFT, uint256 timestamp);

    /// @notice Emitido quando um contrato é removido
    event NFTContractRemoved(address indexed nftContract, uint256 timestamp);

    /// @notice Emitido quando status de contrato muda
    event NFTContractStatusChanged(address indexed nftContract, bool isActive, uint256 timestamp);

    /// @notice Emitido quando um NFT é reciclado
    event NFTRecycled(
        address indexed recycler,
        address indexed nftContract,
        uint256 indexed tokenId,
        uint256 pointsGenerated,
        uint256 timestamp
    );

    /// @notice Emitido quando uma reciclagem falha
    event RecyclingFailed(
        address indexed recycler, address indexed nftContract, uint256 tokenId, string reason, uint256 timestamp
    );

    // ============ Modificadores ============

    /// @notice Verifica se endereço é um contrato válido
    modifier validNFTContract(address _nftContract) {
        require(_nftContract != address(0), "Endereco invalido");
        require(_isContract(_nftContract), "Deve ser um contrato");
        _;
    }

    /// @notice Verifica se NFT está aceito e ativo
    modifier nftIsAccepted(address _nftContract) {
        require(acceptedNFTs[_nftContract].isActive, "NFT nao aceito");
        _;
    }

    // ============ Constructor ============

    constructor() Ownable(msg.sender) {}

    // ============ Funções Administrativas ============

    /**
     * @notice Adiciona um novo contrato NFT à lista de aceitos
     * @param _nftContract Endereço do contrato NFT
     * @param _pointsPerNFT Quantidade de pontos por NFT
     */
    function addAcceptedNFT(address _nftContract, uint256 _pointsPerNFT)
        external
        onlyOwner
        validNFTContract(_nftContract)
    {
        require(_pointsPerNFT > 0, "Pontos devem ser maior que zero");
        require(!acceptedNFTs[_nftContract].isActive, "NFT ja cadastrado");
        require(_supportsERC721(_nftContract), "Nao implementa ERC721");

        acceptedNFTs[_nftContract] =
            NFTConfig({pointsPerNFT: _pointsPerNFT, isActive: true, totalRecycled: 0, dateAdded: block.timestamp});

        emit NFTContractAdded(_nftContract, _pointsPerNFT, block.timestamp);
    }

    /**
     * @notice Atualiza a quantidade de pontos de um NFT
     * @param _nftContract Endereço do contrato NFT
     * @param _newPointsPerNFT Nova quantidade de pontos
     */
    function updateNFTPoints(address _nftContract, uint256 _newPointsPerNFT) external onlyOwner {
        require(acceptedNFTs[_nftContract].dateAdded > 0, "NFT nao cadastrado");
        require(_newPointsPerNFT > 0, "Pontos devem ser maior que zero");

        acceptedNFTs[_nftContract].pointsPerNFT = _newPointsPerNFT;

        emit NFTContractUpdated(_nftContract, _newPointsPerNFT, block.timestamp);
    }

    /**
     * @notice Ativa ou desativa um contrato NFT
     * @param _nftContract Endereço do contrato NFT
     * @param _isActive Status desejado
     */
    function setNFTStatus(address _nftContract, bool _isActive) external onlyOwner {
        require(acceptedNFTs[_nftContract].dateAdded > 0, "NFT nao cadastrado");

        acceptedNFTs[_nftContract].isActive = _isActive;

        emit NFTContractStatusChanged(_nftContract, _isActive, block.timestamp);
    }

    /**
     * @notice Remove um contrato da lista de aceitos
     * @param _nftContract Endereço do contrato NFT
     */
    function removeAcceptedNFT(address _nftContract) external onlyOwner {
        require(acceptedNFTs[_nftContract].dateAdded > 0, "NFT nao cadastrado");

        acceptedNFTs[_nftContract].isActive = false;

        emit NFTContractRemoved(_nftContract, block.timestamp);
    }

    /**
     * @notice Pausa o contrato em caso de emergência
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @notice Despausa o contrato
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    // ============ Funções de Reciclagem ============

    /**
     * @notice Recicla um NFT através de queima (burn)
     * @param _nftContract Endereço do contrato NFT
     * @param _tokenId ID do token a ser reciclado
     * @return pointsGenerated Pontos gerados pela reciclagem
     */
    function recycleNFT(address _nftContract, uint256 _tokenId)
        external
        whenNotPaused
        nftIsAccepted(_nftContract)
        returns (uint256 pointsGenerated)
    {
        IERC721 nft = IERC721(_nftContract);

        // Verifica propriedade
        require(nft.ownerOf(_tokenId) == address(msg.sender), "Nao e o dono do NFT");

        // Tenta fazer burn (se contrato implementar)
        (bool success,) = _nftContract.call(abi.encodeWithSignature("burn(uint256)", _tokenId));

        require(success, "Falha ao queimar NFT - use recycleNFTByTransfer");

        // Obtém pontos
        pointsGenerated = acceptedNFTs[_nftContract].pointsPerNFT;

        // Cria registro
        _createRecyclingRecord(msg.sender, _nftContract, _tokenId, pointsGenerated);

        emit NFTRecycled(msg.sender, _nftContract, _tokenId, pointsGenerated, block.timestamp);

        return pointsGenerated;
    }

    /**
     * @notice Recicla um NFT através de transferência
     * @param _nftContract Endereço do contrato NFT
     * @param _tokenId ID do token a ser reciclado
     * @return pointsGenerated Pontos gerados pela reciclagem
     */
    function recycleNFTByTransfer(address _nftContract, uint256 _tokenId)
        external
        whenNotPaused
        nftIsAccepted(_nftContract)
        returns (uint256 pointsGenerated)
    {
        IERC721 nft = IERC721(_nftContract);

        // Verifica propriedade
        require(nft.ownerOf(_tokenId) == msg.sender, "Nao e o dono do NFT");

        // Transfere NFT para este contrato
        nft.safeTransferFrom(msg.sender, address(this), _tokenId);

        // Obtém pontos
        pointsGenerated = acceptedNFTs[_nftContract].pointsPerNFT;
        // Cria registro
        _createRecyclingRecord(msg.sender, _nftContract, _tokenId, pointsGenerated);

        emit NFTRecycled(msg.sender, _nftContract, _tokenId, pointsGenerated, block.timestamp);

        return pointsGenerated;
    }

    /**
     * @notice Recicla múltiplos NFTs em uma única transação
     * @param _nftContracts Array de endereços dos contratos NFT
     * @param _tokenIds Array de IDs dos tokens
     * @param _useBurn Array indicando se deve usar burn (true) ou transfer (false)
     * @return totalPoints Total de pontos gerados
     */
    function recycleMultipleNFts(
        address[] calldata _nftContracts,
        uint256[] calldata _tokenIds,
        bool[] calldata _useBurn
    ) external whenNotPaused returns (uint256 totalPoints) {
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
     * @notice Função auxiliar para reciclagem em lote (external para try/catch)
     * @dev Não chamar diretamente - use recycleMultipleNFTs
     */
    function recycleSingle(address _nftContract, uint256 _tokenId, bool _useBurn, address _originalCaller)
        external
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
        } else {
            nft.safeTransferFrom(_originalCaller, address(this), _tokenId);
        }

        _createRecyclingRecord(_originalCaller, _nftContract, _tokenId, points);
        emit NFTRecycled(_originalCaller, _nftContract, _tokenId, points, block.timestamp);

        return points;
    }

    // ============ Funções de Consulta ============

    /**
     * @notice Retorna configuração de um contrato NFT
     * @param _nftContract Endereço do contrato
     * @return config Configuração do NFT
     */
    function getNFTConfig(address _nftContract) external view returns (NFTConfig memory) {
        return acceptedNFTs[_nftContract];
    }

    /**
     * @notice Verifica se um NFT está aceito e ativo
     * @param _nftContract Endereço do contrato
     * @return isAccepted True se aceito e ativo
     */
    function isNFTAccepted(address _nftContract) external view returns (bool) {
        return acceptedNFTs[_nftContract].isActive;
    }

    /**
     * @notice Calcula pontos potenciais para quantidade de NFTs
     * @param _nftContract Endereço do contrato
     * @param _quantity Quantidade de NFTs
     * @return points Total de pontos
     */
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

    /**
     * @notice Retorna estatísticas gerais do sistema
     * @return _totalRecyclings Total de reciclagens
     * @return _totalPoints Total de pontos gerados
     * @return activeContracts Número de contratos ativos
     */
    function getStats()
        external
        view
        returns (uint256 _totalRecyclings, uint256 _totalPoints, uint256 activeContracts)
    {
        // Nota: Para produção, considere manter contador de contratos ativos
        return (totalRecyclings, totalPointsGenerated, 0);
    }

    /**
     * @notice Verifica se usuário pode reciclar um NFT
     * @param _user Endereço do usuário
     * @param _nftContract Endereço do contrato NFT
     * @param _tokenId ID do token
     * @return resultCanRecycle Se pode reciclar
     * @return reason Motivo caso não possa
     */
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

    /**
     * @notice Retorna tamanho do histórico
     * @return size Número total de reciclagens
     */
    function getHistorySize() external view returns (uint256) {
        return recyclingHistory.length;
    }

    // ============ Funções Internas ============

    /**
     * @notice Verifica se endereço é um contrato
     * @param _addr Endereço a verificar
     * @return isContract True se for contrato
     */
    function _isContract(address _addr) internal view returns (bool) {
        uint256 size;
        assembly {
            size := extcodesize(_addr)
        }
        return size > 0;
    }

    /**
     * @notice Verifica se contrato implementa ERC721
     * @param _nftContract Endereço do contrato
     * @return supportsInterface True se implementa
     */
    function _supportsERC721(address _nftContract) internal view returns (bool) {
        try IERC721(_nftContract).supportsInterface(INTERFACE_ID_ERC721) returns (bool supported) {
            return supported;
        } catch {
            return false;
        }
    }

    /**
     * @notice Cria e armazena registro de reciclagem
     * @param _recycler Quem reciclou
     * @param _nftContract Contrato do NFT
     * @param _tokenId ID do token
     * @param _points Pontos gerados
     */
    function _createRecyclingRecord(address _recycler, address _nftContract, uint256 _tokenId, uint256 _points)
        internal
    {
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

        // Atualiza contadores
        userRecyclingCount[_recycler]++;
        acceptedNFTs[_nftContract].totalRecycled++;
        totalRecyclings++;
        totalPointsGenerated += _points;
    }

    /**
     * @notice Implementa recebimento de NFTs ERC721
     */
    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return this.onERC721Received.selector;
    }
}
