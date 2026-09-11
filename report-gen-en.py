#!/usr/bin/env python3
"""Generates an AUDIT report (.docx/.doc) in English for the aur.sol contract."""
import zipfile, os
from xml.sax.saxutils import escape

OUT = "/home/openclaw-project/Documentos/aur-natillera-contract/Audit_Report_AUR_Natillera_EN.docx"

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
    out = []
    for ln in text.split("\n"):
        out.append(f'<w:p><w:pPr><w:spacing w:after="0"/></w:pPr>'
                   f'<w:r><w:rPr><w:rFonts w:ascii="Consolas" w:hAnsi="Consolas"/>'
                   f'<w:sz w:val="18"/><w:color w:val="7F6000"/></w:rPr>'
                   f'<w:t xml:space="preserve">{esc(ln)}</w:t></w:r></w:p>')
    return "".join(out)

def table(rows):
    body = ""
    for i, r in enumerate(rows):
        style = '<w:tcPr><w:shd w:val="clear" w:color="auto" w:fill="%s"/></w:tcPr>' % ("D9E2F3" if i==0 else "FFFFFF")
        cells = "".join(f'<w:tc>{style}<w:p><w:pPr><w:spacing w:after="20"/></w:pPr><w:r><w:rPr>{"<w:b/>" if i==0 else ""}<w:sz w:val="18"/></w:rPr><w:t xml:space="preserve">{esc(c)}</w:t></w:r></w:p></w:tc>' for c in r)
        body += f'<w:tr>{cells}</w:tr>'
    return f'<w:tbl><w:tblPr><w:tblW w:w="9000" w:type="dxa"/><w:tblBorders><w:top w:val="single" w:sz="4"/><w:left w:val="single" w:sz="4"/><w:bottom w:val="single" w:sz="4"/><w:right w:val="single" w:sz="4"/><w:insideH w:val="single" w:sz="4"/><w:insideV w:val="single" w:sz="4"/></w:tblBorders></w:tblPr>{body}</w:tbl>' + '<w:p/>'

sec = []
def S(x): sec.append(x)

S(heading("AUR Natillera Contract — Vulnerability Audit Report", 1))
S(para("Project: aur-natillera-contract", bold=True))
S(para("Audited file: src/aur.sol"))
S(para("Analysis date: 2026-09-11"))
S(para("Tools: Slither (static analysis) + manual logic review"))
S(para("Contract: on-chain P2P natillera (rotating saving mechanism, Latin American style)"))
S(para(""))

S(heading("1. Executive Summary", 1))
S(para("The critical finding from the previous audit (AUR-01: over-counting in collected_forTurn(), "
       "which caused an underflow in reStart()) was reported and FIXED. The build and the full test "
       "suite were re-run: 68 tests, all PASSED (0 failures). Slither was re-run against the corrected "
       "code and the High-severity finding is no longer present. 4 Medium, 5 Low, and several "
       "informational/optimization findings remain. The contract is in better shape but still needs "
       "the intermediate findings resolved before being considered production-ready."))
S(para(""))
S(para("Verification status:", bold=True))
S(table([
    ["Step", "Result"],
    ["forge build", "Compiles correctly (only forge-lint typecast warnings)"],
    ["forge test", "68 passed, 0 failed, 0 skipped"],
    ["Slither (post-fix)", "No High-severity findings; 4 Medium, 5 Low, rest Informational/Optimization"],
]))
S(para(""))

S(heading("2. Findings Summary", 1))
S(table([
    ["ID", "Severity", "Location", "Description", "Status"],
    ["AUR-01", "— RESOLVED —", "collected_forTurn()", "Over-counting due to overlapping period ranges → underflow in reStart(). FIXED and verified with 68 tests.", "Resolved ✔"],
    ["AUR-02", "MEDIUM", "deposit_token()", "Allows depositing on any ID without validating ownership; does not verify msg.sender↔ID binding", "Confirmed"],
    ["AUR-03", "MEDIUM", "changeAmount()/changePeriods()", "Global parameters modifiable by any member, breaking economic invariants", "Confirmed"],
    ["AUR-04", "MEDIUM", "updateMember()/addMember()", "Possible ID/address collisions and unauditable membership", "Partial"],
    ["AUR-05", "MEDIUM", "Uninitialized local variables", "total_Collated, UnClaimedMoney, numberActiveMember not initialized (Slither)", "Confirmed"],
    ["AUR-06", "LOW", "period()/reStart()", "Use of block.timestamp for business logic (manipulable by validators)", "Confirmed"],
    ["AUR-07", "INFO", "General", "Naming conventions, pragma version, array length caching", "Informational"],
]))
S(para(""))

S(heading("3. Resolved Finding — AUR-01: Over-counting in collected_forTurn()", 1))
S(heading("3.1 Description", 2))
S(para("The collected_forTurn() function miscalculated the start and end indexes of the period range "
       "assigned to each turn. Ranges overlapped between consecutive turns, so certain periods were "
       "counted more than once. This artificially inflated the total collected amount."))
S(heading("3.2 Vulnerable code (before the fix)", 2))
S(code("""function collected_forTurn(uint64 turn) internal view returns (uint256, uint256) {
    uint256 total_Collated;
    uint256 total_Collated_Late;
    int64 startIndex = ((int64(turn) * int16(s_periods_claim)) - 1) + 1;
    int64 endIndex = (startIndex - (int16(s_periods_claim) - 1)) - 1;  // BUG: extra '- 1'
    for (int64 index = startIndex; index >= endIndex; index--) {
        total_Collated += s_amount_colleted[uint64(index)];
        total_Collated_Late += s_amount_late_colleted[uint64(index)];
    }
    return (total_Collated, total_Collated_Late);
}"""))
S(heading("3.3 Impact (before the fix)", 2))
S(para("With s_periods_claim = 3 and 3 members (9 periods), the contract receives 270 tokens. However, "
       "collected_forTurn() returned amounts summing to 330 (periods 3 and 6 were counted twice). "
       "In reStart(), the operation balanceContract - UnClaimedMoney reverted with panic 0x11 "
       "(arithmetic underflow). The test test_reStart_SecondCycleWorks reproduced it."))
S(heading("3.4 Applied fix", 2))
S(para("The bug was fixed in src/aur.sol by removing the extra '- 1' in the endIndex calculation:"))
S(code("""// BEFORE (bug):
int64 endIndex = (startIndex - (int16(s_periods_claim) - 1)) - 1;

// AFTER (fixed):
int64 endIndex = (startIndex - (int16(s_periods_claim) - 1));

// Now the range covers exactly s_periods_claim periods, with no overlap between turns.
// Turn 1 -> [1,2,3], Turn 2 -> [4,5,6], Turn 3 -> [7,8,9]"""))
S(heading("3.5 Verification (post-fix)", 2))
S(para("The reStart() log after the fix shows correct collection: turn 1 -> collected=30e18 "
       "(3 periods), no duplication; UnClaimedMoney and moneyToDistribute match the balance. "
       "All 68 tests pass (0 failures), including test_reStart_SecondCycleWorks which previously failed."))
S(para(""))

S(heading("4. Medium-Severity Findings", 1))

S(heading("4.1 AUR-02 — deposit_token() does not validate ID ownership", 2))
S(para("deposit_token(uint256 id) deposits the msg.sender's funds assigning them to member id's period, "
       "but without verifying that msg.sender is actually the member with that ID. A malicious member "
       "could deposit on behalf of another member's position, corrupting the per-turn collected amounts."))
S(code("""function deposit_token(uint256 id) external Natillera_Status {
    MemberData storage member = s_members_id[id];
    if (member.addr == address(0)) { revert Wallet__SpenderNotValid(msg.sender); }
    // MISSING: verify that member.addr == msg.sender (or that the authorized SmartContract is calling)
    ..."""))

S(heading("4.2 AUR-03 — Economic parameters modifiable without consensus", 2))
S(para("changeAmount() and changePeriods() only require MEMBER_ROLE and the STARTED state. "
       "Any member can change the amount or the number of periods of the whole natillera mid-cycle, "
       "breaking the collection invariants and the per-turn calculations."))

S(heading("4.3 AUR-04 — Membership management: collisions and access control", 2))
S(para("addMember() and updateMember() handle IDs and addresses with collision risks and without "
       "granular access control. The constructor grants MEMBER_ROLE to the deployer, and any MEMBER "
       "role can add/remove members. DeleteMember() logic pays pending amounts to msg.sender "
       "(not necessarily the removed member) and reorders turns."))

S(heading("4.4 AUR-05 — Uninitialized local variables (Slither)", 2))
S(para("Slither reports local variables used before being explicitly initialized "
       "(total_Collated, total_Collated_Late, UnClaimedMoney, numberActiveMember). Although Solidity "
       "initializes them to 0, the pattern is fragile and in practice masked the over-counting of AUR-01."))
S(para(""))

S(heading("5. Low-Severity Findings", 1))
S(heading("5.1 AUR-06 — Dependence on block.timestamp", 2))
S(para("Period logic (period(), deposit, claim turn, and reStart()) depends on block.timestamp / 30 days. "
       "Validators can marginally manipulate the timestamp, advancing or delaying the claim window. "
       "With 30-day windows the practical risk is low, but business logic should anchor periods to an "
       "explicit counter."))
S(para(""))

S(heading("6. Informational and Optimization Findings", 1))
S(table([
    ["Category", "Detail"],
    ["Array caching", "membersId.length is read on every iteration of 5 loops (cache-array-length)."],
    ["Naming convention", "Functions/variables do not follow mixedCase (Slither naming-convention)."],
    ["Solidity version", "pragma ^0.8.25; consider pinning an exact >=0.8.25 version to avoid divergence."],
    ["Assembly", "Assembly usage in OpenZeppelin imports (StorageSlot, SafeERC20) — expected, not a vulnerability."],
    ["console.log", "forge-std console.sol present in production; adds gas cost and exposes data."],
]))
S(para(""))

S(heading("7. Conclusion and Recommendations", 1))
S(para("The contract is not yet production-ready. The High severity AUR-01 blocked a core flow "
       "(reStart()) and has been fixed by adjusting collected_forTurn() to use non-overlapping ranges. "
       "The Medium findings remain to be addressed."))
S(para("Prioritized recommendations:"))
for rec in [
    "1. Deprecated: the range calculation fix in collected_forTurn() and clean_colleted_money() (AUR-01) — already applied.",
    "2. Add identity validation in deposit_token() (AUR-02).",
    "3. Restrict changeAmount()/changePeriods() to consensus or a dedicated admin role (AUR-03).",
    "4. Harden membership access control and validate that DeleteMember() pays the correct member (AUR-04).",
    "5. Explicitly initialize local variables and remove console.log from production (AUR-05).",
    "6. Consider replacing block.timestamp with a managed period counter (AUR-06).",
]:
    S(para(rec, space_after=60))
S(para(""))
S(para("— End of report —", bold=True))

content = "".join(sec)
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

print("DOCX generated:", OUT, os.path.getsize(OUT), "bytes")
