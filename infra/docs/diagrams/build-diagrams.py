#!/usr/bin/env python3
"""Generate professional Azure-style draw.io diagrams for the student guide.

Official Azure architecture icons (from https://learn.microsoft.com/azure/architecture/icons/)
are embedded as data URIs so the .drawio files are self-contained and render anywhere.
Run: python build-diagrams.py  ->  writes architecture.drawio and access-flow.drawio
Render to PNG with the drawio-export Docker image (see README.md).
"""
import base64
import pathlib
import xml.sax.saxutils as su

HERE = pathlib.Path(__file__).resolve().parent
ICONS = HERE / "icons"

ICON_CACHE = {}


def icon_uri(key: str) -> str:
    if key not in ICON_CACHE:
        data = (ICONS / f"{key}.svg").read_bytes()
        b64 = base64.b64encode(data).decode("ascii")
        ICON_CACHE[key] = f"data:image/svg+xml,{b64}"
    return ICON_CACHE[key]


def esc(text: str) -> str:
    return su.escape(text).replace("\n", "&#10;")


class Diagram:
    def __init__(self, name: str):
        self.name = name
        self.cells = []
        self._id = 1

    def nid(self) -> str:
        self._id += 1
        return f"n{self._id}"

    def container(self, label, x, y, w, h, fill, stroke, dashed=False, font=12, fontcolor="#323130"):
        cid = self.nid()
        dash = "dashed=1;" if dashed else "dashed=0;"
        style = (
            f"rounded=1;whiteSpace=wrap;html=1;{dash}fillColor={fill};strokeColor={stroke};"
            f"verticalAlign=top;fontSize={font};fontColor={fontcolor};fontStyle=1;"
            "arcSize=4;spacingTop=6;spacingLeft=8;align=left;"
        )
        self.cells.append(
            f'<mxCell id="{cid}" value="{esc(label)}" style="{style}" vertex="1" parent="1">'
            f'<mxGeometry x="{x}" y="{y}" width="{w}" height="{h}" as="geometry"/></mxCell>'
        )
        return cid

    def icon(self, label, key, x, y, w=46, h=46, fontsize=11):
        cid = self.nid()
        style = (
            f"shape=image;html=1;image={icon_uri(key)};verticalLabelPosition=bottom;"
            "verticalAlign=top;labelBackgroundColor=none;aspect=fixed;imageAspect=0;"
            f"fontSize={fontsize};fontColor=#323130;"
        )
        self.cells.append(
            f'<mxCell id="{cid}" value="{esc(label)}" style="{style}" vertex="1" parent="1">'
            f'<mxGeometry x="{x}" y="{y}" width="{w}" height="{h}" as="geometry"/></mxCell>'
        )
        return cid

    def label(self, text, x, y, w, h, fontsize=18, bold=True, color="#0B5394", align="left"):
        cid = self.nid()
        style = (
            f"text;html=1;align={align};verticalAlign=middle;whiteSpace=wrap;"
            f"fontSize={fontsize};fontStyle={'1' if bold else '0'};fontColor={color};"
        )
        self.cells.append(
            f'<mxCell id="{cid}" value="{esc(text)}" style="{style}" vertex="1" parent="1">'
            f'<mxGeometry x="{x}" y="{y}" width="{w}" height="{h}" as="geometry"/></mxCell>'
        )
        return cid

    def edge(self, src, tgt, label="", color="#0078D4", dashed=False, width=2, exit_=None, entry=None):
        cid = self.nid()
        dash = "dashed=1;" if dashed else ""
        pts = ""
        if exit_:
            pts += f"exitX={exit_[0]};exitY={exit_[1]};exitDx=0;exitDy=0;"
        if entry:
            pts += f"entryX={entry[0]};entryY={entry[1]};entryDx=0;entryDy=0;"
        style = (
            f"edgeStyle=orthogonalEdgeStyle;rounded=1;html=1;{dash}{pts}"
            f"strokeColor={color};strokeWidth={width};fontSize=11;fontColor=#323130;"
            "labelBackgroundColor=#FFFFFF;endArrow=block;endFill=1;"
        )
        self.cells.append(
            f'<mxCell id="{cid}" value="{esc(label)}" style="{style}" edge="1" parent="1" '
            f'source="{src}" target="{tgt}"><mxGeometry relative="1" as="geometry"/></mxCell>'
        )
        return cid

    def to_xml(self) -> str:
        body = "".join(self.cells)
        diagram_id = self.name.lower().replace(" ", "-")
        return (
            '<mxfile host="app.diagrams.net">'
            f'<diagram id="{diagram_id}" name="{esc(self.name)}">'
            '<mxGraphModel dx="1100" dy="760" grid="0" gridSize="10" guides="1" tooltips="1" '
            'connect="1" arrows="1" fold="1" page="1" pageScale="1" pageWidth="1200" pageHeight="800" '
            'math="0" shadow="0"><root>'
            '<mxCell id="0"/><mxCell id="1" parent="0"/>'
            f'{body}'
            '</root></mxGraphModel></diagram></mxfile>'
        )


def build_architecture() -> str:
    d = Diagram("Per-student architecture")
    d.label("MicroHack SQL 2026 — Per-student environment (example: user01)", 40, 16, 1100, 30, fontsize=18)

    d.container("Microsoft Entra tenant", 40, 80, 210, 560, "#F3F9FE", "#7FBA00", font=12, fontcolor="#5C8A00")
    student = d.icon("Student\n(your laptop)", "user", 110, 120, 56, 56)
    entra = d.icon("Entra ID user\nmhlabuser01@…", "user", 115, 360, 46, 46)

    d.container("Resource group:  rg-mhlab-user01", 290, 80, 850, 600, "#FBFBFB", "#605E5C", dashed=True)
    d.container("Virtual network:  mhlabu01-vnet  (10.0.0.0/16)", 320, 195, 510, 465, "#EAF3FB", "#0078D4")

    d.container("AzureBastionSubnet  (10.0.3.0/24)", 345, 235, 460, 110, "#F6FAFD", "#7AAEDB")
    bastion = d.icon("Azure Bastion\nmhlabu01-bastion", "bastion", 385, 260, 46, 46, fontsize=10)

    d.container("snet-sql  (10.0.1.0/24)", 345, 360, 460, 150, "#F6FAFD", "#7AAEDB")
    srcvm = d.icon("Source VM — SQL Server 2019\nmhlabu01-srcvm", "source-vm", 385, 388, 46, 46, fontsize=10)
    d.icon("NSG\nmhlabu01-sql-nsg", "nsg", 660, 388, 46, 46, fontsize=10)

    d.container("snet-mi  (10.0.4.0/24, delegated)", 345, 525, 460, 120, "#F6FAFD", "#7AAEDB")
    mi = d.icon("SQL Managed Instance\nmhlabu01-sqlmi-…  (MI Link target)", "sql-mi", 385, 552, 46, 46, fontsize=10)

    d.container("Azure SQL  (public endpoint)", 880, 285, 250, 375, "#EAF3FB", "#0078D4")
    srv = d.icon("Azure SQL server\nmhlabu01-sqlsrv-…\n.database.windows.net", "sql-server", 960, 330, 46, 46, fontsize=10)
    db = d.icon("Target database\nyou create it (DMS)", "sql-database", 960, 480, 46, 46, fontsize=10)

    # Per-student Key Vault holding all lab credentials (top strip of the resource group).
    kv = d.icon("Key Vault\nmhlabu01kv…\nvm/sql secrets", "key-vault", 560, 108, 46, 46, fontsize=10)

    # Per-student Log Analytics workspace collecting diagnostics/telemetry.
    law = d.icon("Log Analytics\nmhlabu01-law\ndiagnostics", "log-analytics", 720, 108, 46, 46, fontsize=10)

    d.edge(student, bastion, "RDP in browser (443)", color="#0078D4",
           exit_=(1, 0.5), entry=(0, 0.5))
    d.edge(student, srv, "Portal / SSMS", color="#0078D4",
           exit_=(1, 0.2), entry=(0, 0.2))
    d.edge(entra, srcvm, "RBAC (scoped to the RG):\nContributor + Key Vault Secrets User + VM Admin Login",
           color="#7FBA00", dashed=True, exit_=(1, 0.5), entry=(0, 0.5))
    d.edge(entra, kv, "read secrets", color="#7FBA00",
           dashed=True, exit_=(0.8, 0), entry=(0, 0.8))
    d.edge(srcvm, db, "Challenge 2 — DMS migration", color="#C0392B",
           exit_=(1, 0.5), entry=(0, 0.5))
    d.edge(srcvm, mi, "Challenge 3 — MI Link", color="#8E44AD",
           exit_=(0.5, 1), entry=(0.5, 0))
    d.edge(srcvm, law, "diagnostics / telemetry", color="#605E5C", dashed=True,
           exit_=(0.5, 0), entry=(0.5, 1))

    d.label("AdventureWorks2019 and WideWorldImporters are restored and online on the Source VM.",
            290, 695, 850, 20, fontsize=11, bold=False, color="#605E5C")
    return d.to_xml()


def build_access_flow() -> str:
    d = Diagram("Access flow")
    d.label("Challenge 0 — Access flow (example: user01)", 40, 16, 1000, 30, fontsize=18)

    student = d.icon("Student\n(your laptop)", "user", 60, 150, 60, 60)
    entra = d.icon("1) Sign in — Microsoft Entra ID\nmhlabuser01@…", "user", 230, 150, 50, 50, fontsize=10)
    portal = d.icon("2) Azure Portal\nResource group: rg-mhlab-user01", "azure-sql", 430, 150, 50, 50, fontsize=10)

    bastion = d.icon("3) Azure Bastion\nmhlabu01-bastion", "bastion", 660, 60, 48, 48, fontsize=10)
    srcvm = d.icon("4) Source VM — SQL Server 2019\nmhlabu01-srcvm (SSMS → localhost)", "source-vm", 900, 60, 48, 48, fontsize=10)
    keyvault = d.icon("2a) Key Vault — read VM/SQL\npasswords  mhlabu01kv…", "key-vault", 430, 330, 50, 50, fontsize=9)
    srv = d.icon("5) Azure SQL server (DMS target)\nmhlabu01-sqlsrv-….database.windows.net", "sql-server", 660, 230, 48, 48, fontsize=9)
    mi = d.icon("6) SQL Managed Instance (MI Link)\nmhlabu01-sqlmi-…", "sql-mi", 660, 360, 48, 48, fontsize=10)

    d.edge(student, entra, color="#0078D4")
    d.edge(entra, portal, color="#0078D4")
    d.edge(portal, keyvault, "read secrets", color="#7FBA00", dashed=True, exit_=(0.5, 1), entry=(0.5, 0))
    d.edge(portal, bastion, color="#0078D4", entry=(0.5, 1))
    d.edge(bastion, srcvm, "RDP in browser", color="#0078D4")
    d.edge(portal, srv, color="#0078D4", entry=(0, 0.5))
    d.edge(portal, mi, color="#0078D4", entry=(0, 0.5))

    d.label("Databases on the Source VM: AdventureWorks2019, WideWorldImporters (online).",
            230, 450, 760, 20, fontsize=11, bold=False, color="#605E5C")
    return d.to_xml()


def main():
    (HERE / "architecture.drawio").write_text(build_architecture(), encoding="utf-8")
    (HERE / "access-flow.drawio").write_text(build_access_flow(), encoding="utf-8")
    print("Wrote architecture.drawio and access-flow.drawio")


if __name__ == "__main__":
    main()
