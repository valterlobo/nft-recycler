# NFT Recycler - Sistema de Reciclagem de NFTs

Sistema de smart contracts para reciclagem de NFTs com geração de pontos baseados na pegada de carbono.

## 📋 Índice

- [Visão Geral](#visão-geral)
- [Arquitetura](#arquitetura)
- [Instalação](#instalação)
- [Uso](#uso)
- [Testes](#testes)
- [Deploy](#deploy)
- [Segurança](#segurança)

## 🎯 Visão Geral

O NFT Recycler permite que usuários "reciclem" seus NFTs indesejados, gerando pontos baseados na pegada de carbono estimada do armazenamento desses NFTs. Os NFTs podem ser reciclados através de:

- **Burn (Queima)**: NFT é permanentemente destruído
- **Transferência**: NFT é transferido para um vault (cofre)

### Características Principais

- ✅ Suporte para múltiplos contratos NFT
- ✅ Configuração flexível de pontos por contrato
- ✅ Reciclagem em lote (até 50 NFTs por transação)
- ✅ Histórico completo de reciclagens
- ✅ Pausável em caso de emergência
- ✅ Totalmente testado com Foundry

## 🏗️ Arquitetura

### Contratos

```
src/
├── NFTRecycler.sol          # Contrato principal
└── mocks/
    └── MockNFT.sol           # NFTs mock para testes
```

### Estrutura de Dados

**NFTConfig**: Configuração de cada contrato NFT aceito
```solidity
struct NFTConfig {
    uint256 pointsPerNFT;      // Pontos por NFT
    bool isActive;             // Status ativo/inativo
    uint256 totalRecycled;     // Total reciclado
    uint256 dateAdded;         // Data de inclusão
}
```

**RecyclingRecord**: Registro de cada reciclagem
```solidity
struct RecyclingRecord {
    address recycler;          // Quem reciclou
    address nftContract;       // Contrato do NFT
    uint256 tokenId;           // ID do token
    uint256 pointsGenerated;   // Pontos gerados
    uint256 timestamp;         // Timestamp
    uint256 blockNumber;       // Número do bloco
}
```

## 🚀 Instalação

### Pré-requisitos

- [Foundry](https://book.getfoundry.sh/getting-started/installation)
- Git

### Passos

```bash
# Clone o repositório
git clone https://github.com/seu-usuario/nft-recycler.git
cd nft-recycler

# Instale as dependências
forge install OpenZeppelin/openzeppelin-contracts
forge install foundry-rs/forge-std

# Compile os contratos
forge build

# Execute os testes
forge test
```

## 💻 Uso

### Funções Administrativas

#### Adicionar Contrato NFT Aceito

```solidity
function addAcceptedNFT(address _nftContract, uint256 _pointsPerNFT) external onlyOwner
```

**Exemplo:**
```javascript
// Adiciona NFT que gera 1000 pontos
await recycler.addAcceptedNFT(nftAddress, 1000);
```

#### Atualizar Pontos

```solidity
function updateNFTPoints(address _nftContract, uint256 _newPointsPerNFT) external onlyOwner
```

#### Ativar/Desativar Contrato

```solidity
function setNFTStatus(address _nftContract, bool _isActive) external onlyOwner
```

#### Remover Contrato

```solidity
function removeAcceptedNFT(address _nftContract) external onlyOwner
```

### Funções de Reciclagem

#### Reciclar NFT (Burn)

```solidity
function recycleNFT(address _nftContract, uint256 _tokenId) external returns (uint256 pointsGenerated)
```

**Exemplo:**
```javascript
// Recicla NFT com ID 42
const points = await recycler.recycleNFT(nftAddress, 42);
console.log(`Pontos gerados: ${points}`);
```

#### Reciclar NFT (Transferência)

```solidity
function recycleNFTByTransfer(address _nftContract, uint256 _tokenId) external returns (uint256 pointsGenerated)
```

**Importante:** Requer aprovação prévia:
```javascript
// 1. Aprovar o recycler
await nft.approve(recyclerAddress, tokenId);

// 2. Reciclar
await recycler.recycleNFTByTransfer(nftAddress, tokenId);
```

#### Reciclar Múltiplos NFTs

```solidity
function recycleMultipleNFTs(
    address[] calldata _nftContracts,
    uint256[] calldata _tokenIds,
    bool[] calldata _useBurn
) external returns (uint256 totalPoints)
```

**Exemplo:**
```javascript
const contracts = [nftAddress, nftAddress, nftAddress];
const tokenIds = [1, 2, 3];
const useBurn = [true, true, true];

const totalPoints = await recycler.recycleMultipleNFTs(
    contracts,
    tokenIds,
    useBurn
);
```

### Funções de Consulta

#### Verificar se NFT é Aceito

```solidity
function isNFTAccepted(address _nftContract) external view returns (bool)
```

#### Calcular Pontos Potenciais

```solidity
function calculatePoints(address _nftContract, uint256 _quantity) external view returns (uint256)
```

#### Obter Histórico de Usuário

```solidity
function getUserRecyclingHistory(address _user) external view returns (RecyclingRecord[] memory)
```

#### Verificar se Pode Reciclar

```solidity
function canRecycle(address _user, address _nftContract, uint256 _tokenId) 
    external view returns (bool canRecycle, string memory reason)
```

## 🧪 Testes

### Executar Todos os Testes

```bash
forge test
```

### Testes com Verbosidade

```bash
# Verbosidade nível 2 (mostra logs)
forge test -vv

# Verbosidade nível 3 (mostra stack traces)
forge test -vvv

# Verbosidade nível 4 (mostra tudo)
forge test -vvvv
```

### Executar Teste Específico

```bash
forge test --match-test test_RecycleNFT_Burn_Success
```

### Executar Testes de um Contrato

```bash
forge test --match-contract NFTRecyclerTest
```

### Coverage (Cobertura de Código)

```bash
forge coverage
```

### Gas Report

```bash
forge test --gas-report
```

### Testes Fuzz

Os testes incluem fuzzing automático:

```solidity
function testFuzz_AddAcceptedNFT(uint256 points) public {
    vm.assume(points > 0 && points < type(uint128).max);
    recycler.addAcceptedNFT(address(nftWithBurn), points);
    // ...
}
```

Execute com mais runs para maior confiança:

```bash
forge test --fuzz-runs 10000
```

## 📦 Deploy

### Configuração

Crie um arquivo `.env`:

```env
PRIVATE_KEY=your_private_key_here
MAINNET_RPC_URL=https://eth-mainnet.g.alchemy.com/v2/YOUR-API-KEY
SEPOLIA_RPC_URL=https://eth-sepolia.g.alchemy.com/v2/YOUR-API-KEY
POLYGON_RPC_URL=https://polygon-mainnet.g.alchemy.com/v2/YOUR-API-KEY
ETHERSCAN_API_KEY=your_etherscan_api_key
POLYGONSCAN_API_KEY=your_polygonscan_api_key
```

### Deploy em Testnet

```bash
# Sepolia
forge script script/Deploy.s.sol:DeployNFTRecycler \
    --rpc-url sepolia \
    --broadcast \
    --verify

# Mumbai (Polygon testnet)
forge script script/Deploy.s.sol:DeployNFTRecycler \
    --rpc-url mumbai \
    --broadcast \
    --verify
```

### Deploy em Mainnet

```bash
# Ethereum Mainnet (cuidado!)
forge script script/Deploy.s.sol:DeployNFTRecycler \
    --rpc-url mainnet \
    --broadcast \
    --verify
```

### Deploy de Ambiente de Testes

```bash
forge script script/Deploy.s.sol:DeployTestEnvironment \
    --rpc-url sepolia \
    --broadcast
```

### Setup Pós-Deploy

```bash
# Configure contratos NFT aceitos
RECYCLER_ADDRESS=0x... forge script script/Deploy.s.sol:SetupNFTRecycler \
    --rpc-url mainnet \
    --broadcast
```

## 🔒 Segurança

### Auditorias

- [ ] Auditorias pendentes
- [x] Testes unitários completos
- [x] Testes de integração
- [x] Proteção contra reentrancy
- [x] Pausável em emergências

### Boas Práticas Implementadas

1. **ReentrancyGuard**: Proteção contra ataques de reentrada
2. **Pausable**: Permite pausar em emergências
3. **Ownable**: Controle de acesso administrativo
4. **Checks-Effects-Interactions**: Padrão de segurança seguido
5. **Input Validation**: Validação rigorosa de entradas
6. **SafeMath**: Overflow/underflow protection (Solidity 0.8+)

### Limitações Conhecidas

- Máximo de 50 NFTs por transação em lote (evita gas limit)
- Histórico cresce indefinidamente (considere paginação para grandes volumes)
- Contratos NFT devem implementar ERC721 corretamente



## 🛠️ Desenvolvimento

### Estrutura do Projeto

```
nft-recycler/
├── src/
│   ├── NFTRecycler.sol
│   └── mocks/
│       └── MockNFT.sol
├── test/
│   └── NFTRecycler.t.sol
├── script/
│   └── Deploy.s.sol
├── lib/
│   ├── forge-std/
│   └── openzeppelin-contracts/
├── foundry.toml
├── .env.example
└── README.md
```

### Comandos Úteis

```bash
# Formatar código
forge fmt

# Verificar formatação
forge fmt --check

# Snapshot de gas
forge snapshot

# Limpar build
forge clean

# Atualizar dependências
forge update

# Árvore de dependências
forge tree

# Documentação
forge doc
```

## 🤝 Contribuindo

Contribuições são bem-vindas! Por favor:

1. Fork o projeto
2. Crie uma branch para sua feature (`git checkout -b feature/MinhaFeature`)
3. Commit suas mudanças (`git commit -m 'Adiciona MinhaFeature'`)
4. Push para a branch (`git push origin feature/MinhaFeature`)
5. Abra um Pull Request

### Padrões de Código

- Solidity Style Guide
- Comentários natspec em todas as funções públicas
- 100% de cobertura de testes para novas features
- Gas optimization quando possível

## 🎯 Roadmap

- [x] Contrato principal

- [x] Testes I

- [X] Revisão

- [ ] Testes completos

- [ ] Auditoria

- [ ] Interface web

- [ ] API de integração

  
