// SPDX-License-Identifier: MIT

pragma solidity ^0.8.28;

// Importa il contratto ERC20 di OpenZeppelin per creare un token ERC-20 standard
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
// Importa il contratto Ownable di OpenZeppelin per gestire i privilegi del proprietario
import "@openzeppelin/contracts/access/Ownable.sol";

// Dichiarazione del contratto PINGPONGPLAY, che eredita ERC20 e Ownable
contract PINGPONGPLAY is ERC20, Ownable(address(this)) {
    
    // Mappatura per tenere traccia degli indirizzi bloccati (blacklist)
    mapping(address => bool) public blacklists;

    /**
     * @dev Costruttore del contratto che inizializza il token con un nome e un simbolo.
     * @param _totalSupply La quantità totale di token da generare inizialmente.
     * Il totale viene assegnato all'account che distribuisce il contratto.
     */
    constructor(uint256 _totalSupply) ERC20("PingPongPlay", "PINGPP") {
        _mint(msg.sender, _totalSupply); // Minta tutti i token al creatore del contratto
    }

    /**
     * @dev Aggiunge o rimuove un indirizzo dalla blacklist.
     * Solo il proprietario del contratto può eseguire questa funzione.
     * @param _address L'indirizzo da aggiungere o rimuovere dalla blacklist.
     * @param _isBlacklisting Booleano: `true` per aggiungere, `false` per rimuovere.
     */
    function blacklist(address _address, bool _isBlacklisting) external onlyOwner {
        blacklists[_address] = _isBlacklisting;
    }

    /**
     * @dev Funzione eseguita automaticamente prima di ogni trasferimento di token.
     * Impedisce il trasferimento di token se uno dei due indirizzi (mittente o destinatario) è in blacklist.
     * @param from L'indirizzo del mittente.
     * @param to L'indirizzo del destinatario.
     */
    function _beforeTokenTransfer(
        address from,
        address to
    ) internal virtual {
        require(!blacklists[to] && !blacklists[from], "Blacklisted"); // Blocco dei trasferimenti se l'indirizzo è in blacklist
    }

    /**
     * @dev Permette a un utente di bruciare (distruggere) una quantità di token dal proprio saldo.
     * @param value La quantità di token da bruciare.
     */
    function burn(uint256 value) external {
        _burn(msg.sender, value);
    }
}