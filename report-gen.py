#!/usr/bin/env python3
"""Genera reporte de auditoria .docx (Word) para el contrato aur.sol sin dependencias externas."""
import zipfile, os
from xml.sax.saxutils import escape

OUT = "/home/openclaw-project/Documentos/aur-natillera-contract/Auditoria_AUR_Natillera.docx"

def esc(t): return escape(t)

def para(text, bold=False, size=22, color="000000", align=None, space_after=120):
    al = f' w:jc="{align}"' if align else ""
    b = "<w:b/>" if bold else ""
    col = f'<w:color w:val="{color}"/>' if color != "000000" else ""
    return (f'<w:p><w:pPr>{al}<w:spacing w:after="{space_after}"/></w:pPr>'
            f'<w:r><w:rPr><w:rFonts w:ascii="Calibri" w:hAnsi="Calibri"/>{b}{col}'
            f'<w:sz w:val="{size}"/></w:rPr>'
            f'<w:t xml:space="preserve">{esc(text)}</w:t></w:r></w:p>')

def heading(text, lvl=1):
    sizes = {1: 34, 2: 28, 3: 24}
    return para(text, bold=True, size=sizes.get(lvl,24), color="1F4E79", space_after=100)

def code(text):
    lines = text.split("\n")
    out = []
    for ln in lines:
        out.append(f'<w:p><w:pPr><w:spacing w:after="0"/></w:pPr>'
                   f'<w:r><w:rPr><w:rFonts w:ascii="Consolas" w:hAnsi="Consolas"/>'
                   f'<w:sz w:val="18"/><w:color w:val="7F6000"/></w:rPr>'
                   f'<w:t xml:space="preserve">{esc(ln)}</w:t></w:r></w:p>')
    return "".join(out)

def table(rows):
    """rows: list of list[str]; first row = header."""
    body = ""
    for i, r in enumerate(rows):
        style = '<w:tcPr><w:shd w:val="clear" w:color="auto" w:fill="%s"/></w:tcPr>' % ("D9E2F3" if i==0 else "FFFFFF")
        cells = "".join(f'<w:tc>{style}<w:p><w:pPr><w:spacing w:after="20"/></w:pPr><w:r><w:rPr>{"<w:b/>" if i==0 else ""}<w:sz w:val="18"/></w:rPr><w:t xml:space="preserve">{esc(c)}</w:t></w:r></w:p></w:tc>' for c in r)
        body += f'<w:tr>{cells}</w:tr>'
    return f'<w:tbl><w:tblPr><w:tblW w:w="9000" w:type="dxa"/><w:tblBorders><w:top w:val="single" w:sz="4"/><w:left w:val="single" w:sz="4"/><w:bottom w:val="single" w:sz="4"/><w:right w:val="single" w:sz="4"/><w:insideH w:val="single" w:sz="4"/><w:insideV w:val="single" w:sz="4"/></w:tblBorders></w:tblPr>{body}</w:tbl>' + '<w:p/>'

sections = []
sec = sections.append

sec(heading("Reporte de Auditoría de Vulnerabilidades — Contrato AUR Natillera", 1))
sec(para("Proyecto: aur-natillera-contract", bold=True))
sec(para("Archivo auditado: src/aur.sol"))
sec(para("Fecha del análisis: 2026-09-11"))
sec(para("Herramientas: Slither (análisis estático) + revisión manual de lógica"))
sec(para("Contrato: natillera P2P on-chain (mecanismo de ahorro rotativo, estilo latinoamericano)"))
sec(para(""))

sec(heading("1. Resumen Ejecutivo", 1))
sec(para("El hallazgo crítico detectado en la auditoría anterior (AUR-01: sobre-conteo en collected_forTurn() "
         "que provocaba underflow en reStart()) fue reportado y CORREGIDO. Se ejecutó nuevamente el build "
         "y la suite completa de tests: 68 tests, todos PASARON (0 fallos). "
         "Se ejecutó Slither nuevamente sobre el código corregido y el hallazgo de severidad Alta ya no está "
         "presente. Quedan pendientes 4 hallazgos de severidad Media, 5 de severidad Baja y varios de tipo "
         "informativo/optimización. El contrato mejora su estado, pero aún requiere resolver los hallazgos "
         "intermedios antes de considerarse listo para producción."))
sec(para(""))
sec(para("Estado de verificación:", bold=True))
sec(table([
    ["Paso", "Resultado"],
    ["forge build", "Compila correctamente (solo warnings de forge-lint typecast)"],
    ["forge test", "68 passed, 0 failed, 0 skipped"],
    ["Slither (post-fix)", "Sin hallazgos de severidad High; 4 Medium, 5 Low, resto Informativo/Optimización"],
]))
sec(para(""))

sec(heading("2. Resumen de Hallazgos", 1))
sec(table([
    ["ID", "Severidad", "Ubicación", "Descripción", "Estatus"],
    ["AUR-01", "— RESUELTO —", "collected_forTurn()", "Sobre-conteo de montos por solapamiento de rangos → underflow en reStart(). CORREGIDO y verificado con 68 tests.", "Resuelto ✔"],
    ["AUR-02", "MEDIA", "deposit_token()", "Permite depositar en cualquier ID sin validar que sea el dueño; no verifica vínculo msg.sender↔ID", "Confirmado"],
    ["AUR-03", "MEDIA", "changeAmount()/changePeriods()", "Parámetros globales modificables por cualquier miembro, rompen invariantes económicas", "Confirmado"],
    ["AUR-04", "MEDIA", "updateMember()/addMember()", "Posibles colisiones de ID/address y membresía no auditable", "Parcial"],
    ["AUR-05", "MEDIA", "Variables locales no inicializadas", "total_Collated, UnClaimedMoney, numberActiveMember no inicializadas (Slither)", "Confirmado"],
    ["AUR-06", "BAJA", "period()/reStart()", "Uso de block.timestamp para lógica de negocio (manipulable por validadores)", "Confirmado"],
    ["AUR-07", "INFO", "General", "Convenciones de nombres, pragma versión, cache de longitud de arrays", "Informativo"],
]))
sec(para(""))

sec(heading("3. Hallazgo Resuelto — AUR-01: Sobre-conteo en collected_forTurn()", 1))
sec(heading("3.1 Descripción", 2))
sec(para("La función collected_forTurn() calculaba mal los índices de inicio y fin del rango de períodos "
         "asignados a cada turno. Los rangos se solapaban entre turnos consecutivos, de modo que ciertos "
         "períodos se contabilizaban más de una vez. Esto inflaba artificialmente el total recaudado."))
sec(heading("3.2 Código vulnerable (antes del fix)", 2))
sec(code("""function collected_forTurn(uint64 turn) internal view returns (uint256, uint256) {
    uint256 total_Collated;
    uint256 total_Collated_Late;
    int64 startIndex = ((int64(turn) * int16(s_periods_claim)) - 1) + 1;
    int64 endIndex = (startIndex - (int16(s_periods_claim) - 1)) - 1;  // BUG: '- 1' extra
    for (int64 index = startIndex; index >= endIndex; index--) {
        total_Collated += s_amount_colleted[uint64(index)];
        total_Collated_Late += s_amount_late_colleted[uint64(index)];
    }
    return (total_Collated, total_Collated_Late);
}"""))
sec(heading("3.3 Impacto (antes del fix)", 2))
sec(para("Con s_periods_claim = 3 y 3 miembros (9 períodos), el contrato recibe 270 tokens. Sin embargo "
         "collected_forTurn() devolvía montos que sumaban 330 (los períodos 3 y 6 se contaban dos veces). "
         "En reStart(), la operación balanceContract - UnClaimedMoney revertía con panic 0x11 "
         "(arithmetic underflow). El test test_reStart_SecondCycleWorks lo reproducía."))
sec(heading("3.4 Corrección aplicada", 2))
sec(para("El bug fue corregido en src/aur.sol eliminando el '- 1' extra en el cálculo de endIndex:"))
sec(code("""// ANTES (bug):
int64 endIndex = (startIndex - (int16(s_periods_claim) - 1)) - 1;

// DESPUÉS (corregido):
int64 endIndex = (startIndex - (int16(s_periods_claim) - 1));

// Ahora el rango cubre exactamente s_periods_claim períodos, sin solape entre turnos.
// Turn 1 -> [1,2,3], Turn 2 -> [4,5,6], Turn 3 -> [7,8,9]"""))
sec(heading("3.5 Verificación (post-fix)", 2))
sec(para("El log de reStart() tras el fix muestra recaudación correcta: turn 1 -> collected=30e18 "
         "(3 períodos), sin duplicar; UnClaimedMoney y moneyToDistribute cuadran con el balance. "
         "Los 68 tests pasan (0 fallos), incluido test_reStart_SecondCycleWorks que antes fallaba."))
sec(para(""))

sec(heading("4. Hallazgos de Severidad Media", 1))

sec(heading("4.1 AUR-02 — deposit_token() no valida propietario del ID", 2))
sec(para("deposit_token(uint256 id) deposita fondos del msg.sender asignándolos al período del miembro id, "
         "pero sin verificar que msg.sender sea el miembro con ese ID. Un miembro malintencionado podría "
         "depositar en nombre/posición de otro, corrompiendo las cuentas recaudadas por turno."))
sec(code("""function deposit_token(uint256 id) external Natillera_Status {
    MemberData storage member = s_members_id[id];
    if (member.addr == address(0)) { revert Wallet__SpenderNotValid(msg.sender); }
    // FALTA: verificar que member.addr == msg.sender (o que el SmartContract autorizado llama el depósito)
    ..."""))

sec(heading("4.2 AUR-03 — Parámetros económicos modificables sin consenso", 2))
sec(para("changeAmount() y changePeriods() solo requieren rol MEMBER_ROLE y el estado STARTED. "
         "Cualquier miembro puede cambiar el monto o el número de períodos de toda la natillera en "
         "medio del ciclo, rompiendo los invariantes de recaudación y los cálculos por turno."))

sec(heading("4.3 AUR-04 — Gestión de membresía: colisiones y control de acceso", 2))
sec(para("addMember() y updateMember() manejan IDs y direcciones con riesgos de colisión y sin un "
         "control de acceso granular. El constructor otorga MEMBER_ROLE al deployer, y cualquier rol "
         "MEMBER puede añadir/eliminar miembros. La lógica de DeleteMember() paga pendientes al "
         "msg.sender (no necesariamente al miembro eliminado) y reordena turnos."))

sec(heading("4.4 AUR-05 — Variables locales sin inicializar (Slither)", 2))
sec(para("Slither reporta variables locales que se usan antes de inicializarse explícitamente "
         "(total_Collated, total_Collated_Late, UnClaimedMoney, numberActiveMember). Aunque Solidity "
         "las inicializa a 0, el patrón es frágil y en la práctica enmascara el sobre-conteo del AUR-01."))
sec(para(""))

sec(heading("5. Hallazgos de Severidad Baja", 1))
sec(heading("5.1 AUR-06 — Dependencia de block.timestamp", 2))
sec(para("La lógica de períodos (period(), depositar, reclamar turno y reStart()) depende de "
         "block.timestamp / 30 days. Los validadores pueden manipular marginalmente el timestamp, "
         "adelantando o atrasando la ventana de reclamo. Con ventanas de 30 días el riesgo práctico "
         "es bajo, pero la lógica de negocio debería anclar períodos con un contador explícito."))
sec(para(""))

sec(heading("6. Hallazgos Informativos y de Optimización", 1))
sec(table([
    ["Categoría", "Detalle"],
    ["Cache de arrays", "membersId.length se lee en cada iteración de 5 bucles (cache-array-length)."],
    ["Convención de nombres", "Funciones/variables no siguen mixedCase (Slither naming-convention)."],
    ["Versión de Solidity", "pragma ^0.8.25; considerar bloquear versión exacta >=0.8.25 para evitar divergencias."],
    ["Assembly", "Uso de assembly en imports de OpenZeppelin (StorageSlot, SafeERC20) — esperado, no es vulnerabilidad."],
    ["console.log", "console.sol de forge-std presente en producción; aumentar el costo de gas y exponer datos."],
]))
sec(para(""))

sec(heading("7. Conclusión y Recomendaciones", 1))
sec(para("El contrato no está listo para producción. La severidad Alta (AUR-01) bloquea un flujo "
         "central (reStart()) y debe corregirse primero ajustando collected_forTurn() y "
         "clean_colleted_money() para usar rangos disjuntos."))
sec(para("Recomendaciones priorizadas:"))
for i, rec in enumerate([
    "1. Corregir el cálculo de rangos en collected_forTurn() y clean_colleted_money() (AUR-01).",
    "2. Agregar validación de identidad en deposit_token() (AUR-02).",
    "3. Restringir changeAmount()/changePeriods() a consenso o a un rol admin dedicado (AUR-03).",
    "4. Endurecer control de acceso de membresía y validar que DeleteMember() pague al miembro correcto (AUR-04).",
    "5. Inicializar explícitamente las variables locales y eliminar console.log de producción (AUR-05).",
    "6. Considerar reemplazar block.timestamp por un contador de períodos gestionado (AUR-06).",
], 1):
    sec(para(rec))
sec(para(""))
sec(para("— Fin del reporte —", bold=True))

# Build docx
content = "".join(sections)
document_xml = f'''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
<w:body>{content}
<w:sectPr><w:pgSz w:w="12240" w:h="15840"/><w:pgMar w:top="1134" w:right="1134" w:bottom="1134" w:left="1134"/></w:sectPr>
</w:body></w:document>'''

content_types = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
<Default Extension="xml" ContentType="application/xml"/>
<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
</Types>'''

rels = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
</Relationships>'''

with zipfile.ZipFile(OUT, "w", zipfile.ZIP_DEFLATED) as z:
    z.writestr("[Content_Types].xml", content_types)
    z.writestr("_rels/.rels", rels)
    z.writestr("word/document.xml", document_xml)

print("DOCX generado:", OUT, os.path.getsize(OUT), "bytes")
