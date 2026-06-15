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
    srcvm19 = d.icon("Source VM — SQL Server 2019\nmhlabu01-srcvm19  (DMS source)", "source-vm", 360, 388, 46, 46, fontsize=9)
    srcvm25 = d.icon("Source VM — SQL Server 2025\nmhlabu01-srcvm25  (MI Link source)", "source-vm", 545, 388, 46, 46, fontsize=9)
    d.icon("NSG\nmhlabu01-sql-nsg", "nsg", 720, 388, 46, 46, fontsize=10)

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
    d.edge(entra, srcvm19, "RBAC (scoped to the RG):\nContributor + Key Vault Secrets User + VM Admin Login",
           color="#7FBA00", dashed=True, exit_=(1, 0.5), entry=(0, 0.5))
    d.edge(entra, kv, "read secrets", color="#7FBA00",
           dashed=True, exit_=(0.8, 0), entry=(0, 0.8))
    d.edge(srcvm19, db, "Challenge 2 — DMS migration", color="#C0392B",
           exit_=(0.5, 1), entry=(0, 0.5))
    d.edge(srcvm25, mi, "Challenge 3 — MI Link", color="#8E44AD",
           exit_=(0.5, 1), entry=(0.5, 0))
    d.edge(srcvm25, law, "diagnostics / telemetry", color="#605E5C", dashed=True,
           exit_=(0.5, 0), entry=(0.5, 1))

    d.label("Both Source VMs restore the same databases (AdventureWorks2019, WideWorldImporters). "
            "SQL auth + Microsoft Entra ID auth on the Azure SQL server.",
            290, 695, 850, 20, fontsize=11, bold=False, color="#605E5C")
    return d.to_xml()


def build_access_flow() -> str:
    d = Diagram("Access flow")
    d.label("Challenge 0 — Access flow (example: user01)", 40, 16, 1000, 30, fontsize=18)

    student = d.icon("Student\n(your laptop)", "user", 60, 150, 60, 60)
    entra = d.icon("1) Sign in — Microsoft Entra ID\nmhlabuser01@…", "user", 230, 150, 50, 50, fontsize=10)
    portal = d.icon("2) Azure Portal\nResource group: rg-mhlab-user01", "azure-sql", 430, 150, 50, 50, fontsize=10)

    bastion = d.icon("3) Azure Bastion\nmhlabu01-bastion", "bastion", 660, 60, 48, 48, fontsize=10)
    srcvm19 = d.icon("4a) Source VM — SQL Server 2019\nmhlabu01-srcvm19 (DMS source)", "source-vm", 900, 30, 48, 48, fontsize=9)
    srcvm25 = d.icon("4b) Source VM — SQL Server 2025\nmhlabu01-srcvm25 (MI Link source)", "source-vm", 900, 140, 48, 48, fontsize=9)
    keyvault = d.icon("2a) Key Vault — read VM/SQL\npasswords  mhlabu01kv…", "key-vault", 430, 330, 50, 50, fontsize=9)
    srv = d.icon("5) Azure SQL server (DMS target)\nmhlabu01-sqlsrv-….database.windows.net", "sql-server", 660, 230, 48, 48, fontsize=9)
    mi = d.icon("6) SQL Managed Instance (MI Link)\nmhlabu01-sqlmi-…", "sql-mi", 660, 360, 48, 48, fontsize=10)

    d.edge(student, entra, color="#0078D4")
    d.edge(entra, portal, color="#0078D4")
    d.edge(portal, keyvault, "read secrets", color="#7FBA00", dashed=True, exit_=(0.5, 1), entry=(0.5, 0))
    d.edge(portal, bastion, color="#0078D4", entry=(0.5, 1))
    d.edge(bastion, srcvm19, "RDP in browser", color="#0078D4", exit_=(1, 0.4), entry=(0, 0.5))
    d.edge(bastion, srcvm25, "RDP in browser", color="#0078D4", exit_=(1, 0.6), entry=(0, 0.5))
    d.edge(portal, srv, color="#0078D4", entry=(0, 0.5))
    d.edge(portal, mi, color="#0078D4", entry=(0, 0.5))

    d.label("Both Source VMs have the same databases online: AdventureWorks2019, WideWorldImporters.",
            230, 450, 760, 20, fontsize=11, bold=False, color="#605E5C")
    return d.to_xml()


def build_network() -> str:
    d = Diagram("Network and NSG")
    d.label("MicroHack SQL 2026 — Per-student network & NSG model (example: user01)", 40, 16, 1120, 30, fontsize=18)

    student = d.icon("Student / facilitator\n(public internet)", "user", 50, 360, 56, 56, fontsize=10)

    d.container("Virtual network  mhlabu01-vnet  (10.0.0.0/16)", 230, 90, 600, 660, "#EAF3FB", "#0078D4")

    d.container("AzureBastionSubnet  (10.0.3.0/24)", 260, 140, 540, 150, "#F6FAFD", "#7AAEDB")
    bastion = d.icon("Azure Bastion\nmhlabu01-bastion", "bastion", 300, 175, 46, 46, fontsize=10)
    d.icon("NSG\nBastion-required\ntraffic", "nsg", 620, 175, 46, 46, fontsize=9)

    d.container("snet-sql  (10.0.1.0/24)", 260, 320, 540, 170, "#F6FAFD", "#7AAEDB")
    srcvm19 = d.icon("Source VM — SQL Server 2019\nmhlabu01-srcvm19", "source-vm", 300, 355, 46, 46, fontsize=9)
    srcvm25 = d.icon("Source VM — SQL Server 2025\nmhlabu01-srcvm25", "source-vm", 470, 355, 46, 46, fontsize=9)
    d.icon("NSG\nRDP via Bastion\nSQL 1433", "nsg", 640, 355, 46, 46, fontsize=9)

    d.container("snet-mi  (10.0.4.0/24, delegated to Microsoft.Sql/managedInstances)", 260, 520, 540, 180, "#F6FAFD", "#7AAEDB")
    mi = d.icon("SQL Managed Instance\nmhlabu01-sqlmi-…\n(public endpoint)", "sql-mi", 300, 560, 46, 46, fontsize=9)
    d.icon("NSG\nMI-required ports\n(5022 MI Link)", "nsg", 620, 560, 46, 46, fontsize=9)

    d.container("Public PaaS endpoints  (outside the VNet)", 880, 140, 280, 420, "#EAF3FB", "#0078D4")
    srv = d.icon("Azure SQL server\nmhlabu01-sqlsrv-…\nfirewall: Azure + student", "sql-server", 950, 185, 46, 46, fontsize=9)
    db = d.icon("Target database\nyou create it (DMS)", "sql-database", 950, 330, 46, 46, fontsize=9)
    d.icon("Key Vault\nmhlabu01kv…", "key-vault", 915, 470, 46, 46, fontsize=9)
    d.icon("Log Analytics\nmhlabu01-law", "log-analytics", 1060, 470, 46, 46, fontsize=9)

    d.edge(student, bastion, "443 HTTPS (public)", color="#0078D4", exit_=(1, 0.3), entry=(0, 0.5))
    d.edge(bastion, srcvm19, "browser RDP", color="#0078D4", exit_=(0.4, 1), entry=(0.5, 0))
    d.edge(bastion, srcvm25, "browser RDP", color="#0078D4", exit_=(0.6, 1), entry=(0.5, 0))
    d.edge(student, srv, "portal / SSMS 1433 (public)", color="#0078D4", exit_=(1, 0.7), entry=(0, 0.2))
    d.edge(srcvm19, db, "Challenge 2 — DMS (1433)", color="#C0392B", exit_=(1, 0.5), entry=(0, 0.5))
    d.edge(srcvm25, mi, "Challenge 3 — MI Link (5022)", color="#8E44AD", exit_=(0.5, 1), entry=(0.5, 0))

    d.label("Each student has an isolated VNet; all endpoints are public by design (no private endpoints or peering).",
            230, 705, 600, 20, fontsize=11, bold=False, color="#605E5C")
    return d.to_xml()


def build_isolation() -> str:
    d = Diagram("Subscription isolation")
    d.label("MicroHack SQL 2026 — Subscription isolation (one resource group per student)", 40, 16, 1120, 30, fontsize=18)

    d.container("Azure subscription  (lab tenant)", 40, 70, 1120, 690, "#F3F9FE", "#0078D4")
    d.icon("Subscription", "subscription", 70, 92, 38, 38, fontsize=9)
    d.label("Deployed by the infra/ automation (deploy.ps1 or the web UI). Each student index NN → one isolated resource group.",
            120, 96, 1000, 30, fontsize=12, bold=False, color="#323130")

    # Expanded example: user01.
    d.container("rg-mhlab-user01", 70, 150, 300, 560, "#FBFBFB", "#605E5C", dashed=True)
    d.icon("Entra ID user — mhlabuser01@…\nRBAC scoped to this RG", "user", 100, 180, 40, 40, fontsize=8)
    d.icon("Source VM — SQL 2019\nmhlabu01-srcvm19", "source-vm", 100, 260, 44, 44, fontsize=8)
    d.icon("Source VM — SQL 2025\nmhlabu01-srcvm25", "source-vm", 250, 260, 44, 44, fontsize=8)
    d.icon("Azure SQL server\nmhlabu01-sqlsrv-…", "sql-server", 100, 360, 44, 44, fontsize=9)
    d.icon("SQL Managed Instance\nmhlabu01-sqlmi-…", "sql-mi", 100, 450, 44, 44, fontsize=9)
    d.icon("Key Vault\nmhlabu01kv…", "key-vault", 100, 540, 44, 44, fontsize=9)
    d.icon("Log Analytics\nmhlabu01-law", "log-analytics", 100, 630, 44, 44, fontsize=9)
    d.icon("Azure Bastion\nmhlabu01-bastion", "bastion", 250, 360, 44, 44, fontsize=9)
    d.label("VNet 10.0.0.0/16\n(isolated)", 235, 450, 130, 40, fontsize=10, bold=False, color="#605E5C")

    # Collapsed, identical copies.
    for xx, name in ((400, "rg-mhlab-user02"), (640, "rg-mhlab-user03")):
        d.container(name, xx, 150, 210, 560, "#FBFBFB", "#605E5C", dashed=True)
        d.icon("Identical, isolated stack", "resource-group", xx + 75, 390, 60, 60, fontsize=10)

    d.container("rg-mhlab-userNN", 880, 150, 250, 560, "#FBFBFB", "#605E5C", dashed=True)
    d.label("…", 970, 300, 70, 70, fontsize=44, bold=True, color="#605E5C", align="center")
    d.label("up to N students\n(userCount parameter)", 905, 480, 200, 40, fontsize=11, bold=False, color="#605E5C", align="center")

    d.label("No VNet peering, no shared resources, no cross-RG RBAC — students cannot reach each other's environments.",
            70, 720, 900, 18, fontsize=11, bold=False, color="#605E5C")
    d.label("Teardown: scripts\\cleanup.ps1 deletes every rg-mhlab-user* resource group and its Entra ID user.",
            70, 740, 900, 18, fontsize=11, bold=False, color="#C0392B")
    return d.to_xml()


def main():
    (HERE / "architecture.drawio").write_text(build_architecture(), encoding="utf-8")
    (HERE / "access-flow.drawio").write_text(build_access_flow(), encoding="utf-8")
    (HERE / "network.drawio").write_text(build_network(), encoding="utf-8")
    (HERE / "isolation.drawio").write_text(build_isolation(), encoding="utf-8")
    print("Wrote architecture.drawio, access-flow.drawio, network.drawio and isolation.drawio")


if __name__ == "__main__":
    main()
