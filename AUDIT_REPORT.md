# Reporte de Auditoría — Contrato AUR (Natillera)

**Fecha:** 2026-09-09 (revisión 2 — tras cambios del autor)
**Contrato analizado:** `src/aur.sol` (713 líneas)
**Herramientas:** Slither 0.11.6, Echidna 2.3.3, análisis manual (entry-point-analyzer)
**Estado del contrato:** Work in progress, no auditado, no apto para producción (según su propio `@dev`)

---

## 1. Resumen Ejecutivo

El contrato `aur` implementa una natillera on-chain: un grupo de personas ahorra
juntos y retira el dinero por turnos.

**Cambios del autor desde la revisión 1:**
- ✅ **`updateMember` corregido** — el bug crítico de `==` en vez de `=` fue arreglado
  (ahora usa `delete s_members_addr[member.addr]` y `s_members_addr[newAdr] = id`).
- ✅ **`DeleteMember` mejorado** — ahora limpia `s_members_addr`, revoca el rol, y borra
  `s_members_turn` y `s_members_id`.
- ⚠️ **`deleteMember` sigue vacío** (placeholder, no revoca el rol).
- ⚠️ **`updateMember` sigue sin `onlyRole`** (superficie de ataque sin restricción).

**Estado actual:** 50 tests pasando, 3 invariantes Echidna pasando, Slither reporta
hallazgos de calidad (sin bugs críticos nuevos tras los fixes).

**Veredicto:** Mejoró respecto a la revisión 1 (bug crítico de `updateMember` resuelto),
pero **sigue sin ser apto para producción** por la superficie de ataque de
`updateMember` y la lógica incompleta de `deleteMember`.

---

## 2. Herramientas y Ejecución

| Herramienta | Versión | Resultado |
|-------------|---------|-----------|
| Slither | 0.11.6 | Hallazgos de calidad (sin bugs críticos nuevos) |
| Echidna | 2.3.3 | 3 invariantes, 20,133 llamadas, todas **passing** |
| Foundry tests | — | **50 passed, 0 failed** |
| Análisis manual | — | Mapeo de entry points + revisión de lógica |

---

## 3. Hallazgos de Seguridad

### ✅ RESUELTO — Bug crítico en `updateMember` (revisión 1)

**Antes (revisión 1):**
```solidity
s_members_addr[member.addr] == 0;   // == en vez de = (no actualizaba)
s_members_addr[newAdr] == id;       // == en vez de = (no actualizaba)
```

**Ahora (revisión 2):**
```solidity
delete s_members_addr[member.addr];
s_members_addr[newAdr] = id;
```

**Estado:** ✅ Corregido. El mapping `s_members_addr` ahora se actualiza correctamente.

---

### 🟠 ALTO — `updateMember` sigue siendo público (sin `onlyRole`)

**Ubicación:** `src/aur.sol:343`

`updateMember` no tiene `onlyRole(MEMBER_ROLE)`. Solo verifica que
`member.SmartContract == msg.sender`. Si un miembro tiene su `SmartContract` apuntando
a su propia wallet (como en los tests: `addMember(id, member, member)`), cualquier
persona que controle esa wallet puede llamar `updateMember` y transferir la membresía
a otra dirección, revocando el rol del dueño legítimo.

**Impacto:** Robo de membresía / control de la cuenta de un miembro.

**Severidad:** Alta (si el patrón de `SmartContract = wallet` se usa en producción).

#### Ejemplo de explotación (POC) — Robo de membresía

**Escenario:** El admin agrega a `victim` con su propia wallet como `SmartContract`
(patrón usado en los tests: `addMember(id, addr, addr)`). Un atacante que controle esa
wallet (o la propia víctima comprometida) puede transferir la membresía.

**Secuencia de ataque:**

1. **Setup:** El admin agrega a la víctima con `SmartContract = victim`.
   ```solidity
   aurContract.addMember(1, victim, victim); // SmartContract = victim (su wallet)
   ```

2. **Ataque:** Quien controle la wallet de la víctima llama `updateMember(1, attacker)`.
   Como `member.SmartContract == victim == msg.sender`, el check pasa (no hay `onlyRole`):
   ```solidity
   aurContract.updateMember(1, attacker);
   // -> delete s_members_addr[victim]
   // -> s_members_addr[attacker] = 1
   // -> _revokeRole(MEMBER_ROLE, victim)
   // -> member.addr = attacker
   // -> _grantRole(MEMBER_ROLE, attacker)
   ```

3. **Resultado:** El atacante ahora tiene `MEMBER_ROLE` y `member.addr = attacker`.
   Puede depositar, reclamar turnos (`claim_myTurn`) y retirar fondos en nombre del
   miembro original. La víctima pierde el acceso a su membresía y a sus fondos.

**Test que demuestra el robo (Foundry):**
```solidity
function test_updateMember_MembershipTheft() public {
    // Setup: admin agrega a victim con su wallet como SmartContract
    vm.prank(member1);
    aurContract.addMember(1, victim, victim);
    assertTrue(aurContract.hasRole(aurContract.MEMBER_ROLE(), victim));

    // Ataque: quien controla el SmartContract transfiere la membresía
    vm.prank(victim);
    aurContract.updateMember(1, attacker);

    // Resultado: el atacante tiene el rol, la víctima lo perdió
    assertTrue(aurContract.hasRole(aurContract.MEMBER_ROLE(), attacker));
    assertFalse(aurContract.hasRole(aurContract.MEMBER_ROLE(), victim));

    (aur.MemberData memory m, , ) = aurContract.getdataMember(1);
    assertEq(m.addr, attacker); // la membresía ahora pertenece al atacante
}
```

**Mitigación:** Agregar `onlyRole(MEMBER_ROLE)` a `updateMember` y/o restringir que
`SmartContract` no pueda ser una wallet EOA (debe ser un contrato).

---

### 🟡 MEDIO — `deleteMember` sigue vacío (placeholder)

**Ubicación:** `src/aur.sol:441`

```solidity
function deleteMember(uint256 id) external onlyRole(MEMBER_ROLE) {
    // we need to remove grant role
}
```

**Problema:** El cuerpo está vacío. No revoca el rol, no limpia mappings, no decrementa
`s_total_member`. Un miembro "eliminado" sigue teniendo `MEMBER_ROLE` y acceso completo.

**Impacto:** La función no cumple su propósito. Si se usa para expulsar miembros, no
funciona.

**Severidad:** Media (depende de si se usa en producción).

---

### 🟡 MEDIO — Dependencia de `block.timestamp` para lógica de negocio

**Ubicación:** `deposit_token` (237), `members_status` (545), `is_myTurn` (620),
`period()` (697)

El contrato usa `block.timestamp` para calcular periodos de 30 días. Un validador
puede manipular el timestamp dentro de una ventana de ~15 segundos, y en redes
permisionadas el control es total. Para una natillera (ahorro a largo plazo), la
manipulación puede adelantar/atrasar turnos de cobro.

**Severidad:** Media (depende del entorno de despliegue).

---

### 🟡 MEDIO — Estado sin inicializar

**Ubicación:**
- `s_amount_late` (línea 111) — nunca se inicializa ni se escribe, solo se lee en
  `getData()`. Siempre devuelve 0 (código muerto).
- Variables locales sin inicializar: `total_Collated` (563), `total_Collated_Late` (564),
  `numberActiveMember` (541).

**Impacto:** `s_amount_late` es código muerto que siempre reporta 0. Las variables
locales dependen del valor por defecto (0), lo que funciona pero es frágil.

---

## 4. Hallazgos de Calidad (Slither)

| Detector | Hallazgo | Ubicación |
|----------|----------|-----------|
| `naming-convention` | Contrato y funciones no siguen `mixedCase`/`CapWords` | Todo el contrato |
| `cache-array-length` | `membersId.length` en loop sin cachear | líneas 513, 543 |
| `constable-states` | `s_amount_late` debería ser constante | línea 111 |
| `boolean-equal` | `m_ismyturn == false`, `member.claim == true` (usar `!`) | líneas 285, 288 |
| `uninitialized-state` | `s_amount_late` nunca inicializado | línea 111 |
| `uninitialized-local` | `total_Collated`, `total_Collated_Late`, `numberActiveMember` | 541, 563, 564 |
| `timestamp` | Uso de `block.timestamp` en comparaciones | 237, 545, 620 |
| `solc-version` | Pragma `^0.8.25` en contrato vs `^0.8.24` en tests | — |

**Nota:** El detector `redundant-statements` (que antes marcaba `s_members_id;` en
`deleteMember`) ya no aparece porque el cuerpo de `deleteMember` quedó vacío.

---

## 5. Resultados de Echidna (Fuzzing)

**3 invariantes, 20,133 llamadas, todas passing:**

| Invariante | Resultado |
|------------|-----------|
| `echidna_contract_balance_bounded` (balance del contrato ≤ 3000 ether) | ✅ passing |
| `echidna_pending_claim_bounded` (pendingClaim ≤ amount × periods) | ✅ passing |
| `echidna_member_count_bounded` (total miembros ≤ 3) | ✅ passing |

**Cobertura:** 4,503 instrucciones únicas, 3 contratos, corpus de 2 secuencias.

**Limitación:** Las invariantes no detectan el robo de membresía de `updateMember`
porque no exploran la secuencia exacta (llamar `updateMember` y verificar el rol).
Se recomienda agregar una invariante que verifique la consistencia de
`s_members_addr` ↔ `s_members_id` y el control de acceso.

---

## 6. Entry Points (Superficie de Ataque)

**11 funciones que cambian estado:**

### Públicas (sin restricción) — prioridad
| Función | Línea | Riesgo |
|---------|-------|--------|
| `updateMember(id, newAdr)` | 343 | 🟠 Sin `onlyRole`, solo check de SmartContract |

### Role-restricted (MEMBER_ROLE)
| Función | Línea | Modifiers |
|---------|-------|-----------|
| `deposit_token(id)` | 215 | `Natillera_Status` |
| `changeAmount` | 251 | `onlyRole` + `Natillera_Status_Started` |
| `changePeriods` | 262 | `onlyRole` + `Natillera_Status_Started` |
| `claim_myTurn(id)` | 276 | `Member_Status` + `onlyRole` + `nonReentrant` |
| `addMember` | 386 | `onlyRole` |
| `startNatillera` | 424 | `onlyRole` + `Natillera_Status_Started` |
| `deleteMember` | 441 | `onlyRole` (pero vacío) |
| `ChangeTurn` | 459 | `Natillera_Status_Started` + `onlyRole` |
| `DeleteMember` | 509 | `Natillera_Status_Started` + `onlyRole` |
| `reStart` | 361 | placeholder vacío |

---

## 7. Recomendaciones (Priorizadas)

1. **ALTO:** Agregar `onlyRole(MEMBER_ROLE)` a `updateMember`, o restringir que
   `SmartContract` no pueda ser una wallet EOA.
2. **ALTO:** Implementar `deleteMember` — revocar rol, limpiar mappings, decrementar
   `s_total_member`.
3. **MEDIO:** Eliminar `s_amount_late` (código muerto) o inicializarlo/actualizarlo.
4. **MEDIO:** Evaluar el riesgo de `block.timestamp` según el entorno de despliegue.
5. **BAJO:** Inicializar variables locales, cachear `membersId.length`, seguir
   convenciones de naming, usar `!` en vez de `== false`.

---

## 8. Archivos Analizados

- `src/aur.sol` — contrato principal (713 líneas, 11 entry points que cambian estado)
- `test/aur.t.sol` — suite de tests (50 tests, todos pasando)
- `test/invariants/AURInvariants.sol` — harness de invariantes Echidna

---

*Reporte generado con Slither 0.11.6, Echidna 2.3.3 y análisis manual siguiendo la
metodología de Trail of Bits (entry-point-analyzer, property-based-testing).*
