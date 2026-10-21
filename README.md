# WPS-PowerAddons

WPS-PowerAddons is een Nederlandstalige, uitbreidbare Windows-supporttoolkit voor IT-supportmedewerkers. De Windows Forms-dashboardapplicatie bundelt diagnose, informatieverzameling en herstelacties voor SAP, Microsoft 365, netwerk, Windows, printers, hardware en support. De applicatie-ID is `WPS.PowerAddons`.

## Ondersteuning en vereisten

- Windows 10 en Windows 11 (64-bit).
- Windows PowerShell 5.1 en .NET Framework/Windows Forms, beide onderdeel van Windows.
- Er zijn geen externe PowerShell-modules vereist.
- De GUI start als de aangemelde gebruiker. Alleen een geselecteerde tool met `RequiresAdmin: true` vraagt zo nodig via Windows UAC om verhoging; de GUI wordt niet opnieuw gestart als administrator.
- Een standaardgebruiker kan alle niet-beheertools gebruiken. Een geannuleerd UAC-verzoek wordt als `Cancelled` vastgelegd.

## Starten en installeren

### Installeren vanuit een verse PowerShell-sessie

Na publicatie van deze repository kan de actuele installer vanuit Windows PowerShell 5.1 worden gestart met:

```powershell
irm https://raw.githubusercontent.com/Dvanhaeften/WPS-PowerAddons/main/install.ps1 | iex
```

De installer downloadt de bootstrap en de repository via HTTPS, slaat tijdelijke bestanden op in een unieke map, en installeert voor de huidige gebruiker onder `%LOCALAPPDATA%\WPS-PowerAddons`. Bekijk `install.ps1` eerst voordat je het uitvoert; een pipeline naar `iex` voert externe code direct uit. Deze route vereist dat de GitHub-repository openbaar is. `wps-poweraddons/win` is op zichzelf geen geldige GitHub-URL; gebruik de volledige URL hierboven.

### Portable

Pak `WPS-PowerAddons.zip` uit en start `Start-WPS-PowerAddons.cmd`, of start expliciet:

```powershell
PowerShell.exe -STA -NoProfile -ExecutionPolicy Bypass -File .\WPS-PowerAddons.ps1
```

Portable slaat logs lokaal op in `logs\`, wijzigt geen registerinstellingen en maakt geen service of geplande taak aan. Maak een bestaande portable-map niet leeg bij updates: behoud `logs\`, `config\settings.json` en `custom-tools\`.

### Installatie voor de huidige gebruiker (standaard)

```powershell
PowerShell.exe -NoProfile -ExecutionPolicy Bypass -File .\bootstrap.ps1
PowerShell.exe -NoProfile -ExecutionPolicy Bypass -File .\bootstrap.ps1 -Scope CurrentUser
```

De installatie gebruikt `%LOCALAPPDATA%\WPS-PowerAddons`; logs staan in `%LOCALAPPDATA%\WPS-PowerAddons\Logs`. Voor deze scope wordt geen UAC gevraagd.

### Machinebrede installatie

```powershell
PowerShell.exe -NoProfile -ExecutionPolicy Bypass -File .\bootstrap.ps1 -Scope AllUsers
```

De installatie gebruikt `%ProgramData%\WPS-PowerAddons` en `%ProgramData%\WPS-PowerAddons\Logs`. Alleen deze scope vraagt na bevestiging om UAC. De verhoogde bootstrap installeert; de aanroeper start de GUI als de oorspronkelijke aangemelde gebruiker. Als ProgramData of de logmap niet schrijfbaar is, wordt een lokale logmap gebruikt en vastgelegd.

### ZIP-pakket installeren of bijwerken

```powershell
PowerShell.exe -NoProfile -ExecutionPolicy Bypass -File .\bootstrap.ps1 -Scope CurrentUser -PackagePath .\WPS-PowerAddons.zip -ExpectedSha256 "VUL_HIER_DE_64_TEKENS_SHA256_IN"
PowerShell.exe -NoProfile -ExecutionPolicy Bypass -File .\bootstrap.ps1 -Scope CurrentUser -PackageUrl "https://intranet.example/WPS-PowerAddons.zip" -ExpectedSha256 "VUL_HIER_DE_64_TEKENS_SHA256_IN"
```

De bootstrap downloadt eerst het complete HTTPS-pakket, controleert desgewenst SHA-256, valideert ZIP-paden en projectbestanden en pakt alleen uit in een tijdelijke map. Een foutieve hash stopt de installatie. Publiceer pakketten op een vertrouwde interne HTTPS-host en verspreid de hash via een onafhankelijk kanaal. De update gebruikt een stagingmap en bewaart instellingen, logs en `custom-tools`. `ExecutionPolicy Bypass` geldt alleen voor het gestart PowerShell-proces; systeem- en gebruikersbeleid wordt niet aangepast. Download nooit een niet-geverifieerd pakket.

## Dashboard en interface

De GUI is volledig Nederlandstalig en toont versie, computer, gebruiker en de actuele administrator-/standaardgebruikerscontext. Gebruik de zijbalk voor Dashboard, alle tools, SAP, Microsoft 365, Netwerk, Windows, Printers, Hardware, Support, Mijn tools, Tool toevoegen, Beheer, Instellingen, Logboeken en Over WPS-PowerAddons.

Zoeken werkt op naam, beschrijving, categorie, tags en ID. Toolkaarten tonen categorie, versie, beschrijving, bron en administratorvereiste. Filter standaardgebruikers-tools en favorieten en sorteer op naam, categorie, beheerdersvereiste, recent gebruik, bron of favoriet. Alleen-lezen uitvoeren is beschikbaar als de tool dat ondersteunt. De configuratie kan zonder herstart worden vernieuwd.

Tools worden in een apart PowerShell-proces uitgevoerd; de interface blijft beschikbaar. Een time-out stopt de PowerShell-runner, maar kan een al gestart extern Windows-proces niet in alle gevallen veilig beëindigen. Daarom meldt de interface dit als time-out en beweert zij niet dat alle onderliggende processen zijn geannuleerd. Een expliciete annulering kan per tool niet veilig worden gegarandeerd. Tooluitvoer wordt alleen in het resultaatvenster getoond, niet in logs.

## Ingebouwde tools

| Categorie | Zonder administratorrechten | Administratorrechten vereist |
| --- | --- | --- |
| Netwerk | Netwerkdiagnose, DNS-configuratie controleren | DNS-cache wissen, Winsock resetten |
| Support | Computerinformatie, supportoverzicht, gebruikersinformatie, PowerShell-opdracht uitvoeren | — |
| Hardware | Batterijrapport, schijfruimte | — |
| SAP | SAP-informatie, loglocaties, installer alleen ontdekken | SAP LocalGUI herstellen |
| Microsoft 365 | Teams-/OneDrive-informatie, connectiviteit, OneDrive-reset, Teams-cache | — |
| Printers | — | Printerwachtrijservice herstarten |
| Windows | — | DISM ScanHealth, DISM RestoreHealth, SFC, Windows Update-services herstarten |

OneDrive-reset en Teams-cachebeheer zijn wijzigingen onder het account van de gebruiker en vragen daarom geen administratorrechten. Ze vragen wel expliciete bevestiging. Teams wordt niet automatisch afgesloten; cache wordt niet gewist als Teams nog actief is. SAP LocalGUI-herstel sluit SAP/Excel niet automatisch, vraagt bevestiging na het tonen van het gevonden pad en start de installer alleen in een apart proces met een procesgebonden `ExecutionPolicy Bypass`. DISM/SFC-uitvoer wordt in het resultaatvenster getoond. Geen tool start automatisch een herstart.

**PowerShell-opdracht uitvoeren** toont een invoervenster waarin u de opdracht kunt controleren en expliciet bevestigen. De opdracht draait in een apart PowerShell-proces met uw huidige gebruikersrechten; de app vraagt hiervoor geen UAC en slaat opdrachttekst noch uitvoer op in logs. Opdrachten kunnen wel gegevens wijzigen of verwijderen. Voer alleen opdrachten uit die u begrijpt en vertrouwt; interactieve opdrachten worden niet ondersteund.

Voorbeeld van een alleen-lezenopdracht in de tool:

```powershell
Get-ComputerInfo | Select-Object WindowsProductName, WindowsVersion
```

## Een nieuwe tool toevoegen

Gebruik **Tool toevoegen** om een bestaand `.ps1`-bestand te importeren. De GUI controleert ID en bestand, toont een waarschuwing dat PowerShell-code de computer kan wijzigen, kopieert het script naar `custom-tools\<tool-id>\` en registreert een SHA-256-hash in `custom-tools\custom-tools.json`. Import voert het script nooit uit. De toolconfiguratie wordt tijdelijk geschreven, geparseerd en pas na validatie atomisch vervangen; er wordt een back-up gemaakt.

### Compleet voorbeeld

Maak `controleer-host.ps1`:

```powershell
[CmdletBinding()]
param([switch]$ReadOnly)
$ErrorActionPreference = 'Stop'
try {
    $computer = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
    Write-Output ('Computer: {0}' -f $computer.Name)
    exit 0
} catch {
    Write-Error ('Computercontrole mislukt: {0}' -f $_.Exception.Message)
    exit 1
}
```

Kies in de GUI de bestandslocatie en vul bijvoorbeeld dit metadata-object in:

```json
{
  "Id": "controleer-host",
  "Name": "Host controleren",
  "Category": "Support",
  "Description": "Toont de computernaam zonder instellingen te wijzigen.",
  "RequiresAdmin": false,
  "RequiresConfirmation": false,
  "SupportsReadOnlyMode": true,
  "Enabled": true,
  "Favourite": false,
  "Version": "1.0.0",
  "Author": "Support",
  "Tags": ["computer", "controle"],
  "RestartBehaviour": "None",
  "TimeoutSeconds": 60
}
```

De GUI berekent zelf het relatieve scriptpad en de SHA-256-hash; wijzig die hash niet handmatig. **Configuratie controleren** en **Tool testen** controleren het metadata-object en de PowerShell-syntaxis; het script wordt niet automatisch uitgevoerd. Gebruik `templates\Example-Tool.ps1` als startpunt. Het template controleert een vereiste opdracht, behandelt fouten, toont leesbare uitvoer en schrijft een voorbeeldbestand veilig. De instelling `RequiresAdmin` bepaalt alleen de launch-context van de tool; tools mogen zelf geen UAC-bypass implementeren.

### Handmatig een ingebouwde tool toevoegen

Voeg een object met de hieronder beschreven eigenschappen toe aan `config\tools.json`. Kies een unieke lowercase ID met cijfers en koppeltekens. `Script` moet een relatief `.ps1`-pad binnen de toepassingsmap zijn; absolute paden en `..` zijn verboden. Plaats het script onder `functions\<Categorie>\`, controleer de tool met de projectvalidatie en gebruik **Configuratie vernieuwen**.

### Aangepaste tools beheren, exporteren en importeren

Mijn tools toont aangepaste tools en laat ze uit de registratie verwijderen. De registratie krijgt eerst een back-up; logs blijven behouden. Het verwijderen van de scriptmap is een afzonderlijke bevestigingskeuze. ZIP-export bevat script, `metadata.json` (met hash), README en versie. ZIP-import controleert padnamen, ID, script en SHA-256 vóór installatie, extraheert alleen naar een tijdelijke validatiemap en voert nooit code uit. Controleer de bron van iedere tool voor gebruik.

## Configuratie

`config\tools.json` is de ingebouwde toolregistry. Elk object vereist:

`Id`, `Name`, `Category`, `Description`, `Script`, `RequiresAdmin`, `RequiresConfirmation`, `SupportsReadOnlyMode`, `Enabled`, `Visible`, `Favourite`, `Version`, `Author`, `Source`, `Tags`, `RestartBehaviour` en `TimeoutSeconds`.

`Source` is `BuiltIn` of `Custom`; `RestartBehaviour` is `None`, `Recommended` of `Required`. ID's zijn uniek; tags zijn een lijst strings; time-outs zijn 10 t/m 7200 seconden. Scriptpaden moeten bestaan en binnen de projectroot blijven. Fouten worden in het logboek opgenomen; ongeldige records worden niet uitvoerbaar. Een ongeldige aangepaste record verhindert niet dat andere geldige tools worden geladen.

`custom-tools\custom-tools.json` bevat uitsluitend metadata voor maatwerktools, inclusief `Sha256`; de ingebouwde `tools.json` wordt door de toolmanager niet gewijzigd. `config\settings.json` bevat versie, taal, thema, weergave, installatiescope, logretentie, hashcontrole, standaardtime-out, editorvoorkeur en gebruikersfavorieten/recent gebruikt. Instellingen worden gevalideerd en met een back-up atomisch bijgewerkt.

## Logging en exitcodes

Dagelijkse toepassingslogs, een JSON-uitvoeringslog per run en `index.json` staan in de scope-afhankelijke logmap. Standaardretentie is 30 dagen en is instelbaar. Logbestanden ouder dan de retentie kunnen op de pagina Logboeken alleen na bevestiging worden verwijderd. Logs registreren tijdstippen, computer/accountnaam, PID, tool, modus, exitcode, status, resultaatmelding en herstartadvies; uitvoer, wachtwoorden, tokens en credentials worden niet opgeslagen.

| Code | Betekenis |
| ---: | --- |
| 0 | Success |
| 1 | GeneralError |
| 2 | UserCancelled |
| 3 | AdministratorRightsUnavailable |
| 4 | PrerequisiteMissing |
| 5 | RestartRecommended |
| 6 | RestartRequired |
| 7 | ValidationFailed |
| 8 | Timeout |
| 9 | ScriptHashChanged |

## Publicatie en Authenticode

Maak `WPS-PowerAddons.zip` met `WPS-PowerAddons-Package.ps1`. De builder sluit logs en persoonlijke custom tools uit, refuseert een bestaand doelbestand en toont na afloop de SHA-256-hash. Publiceer het pakket via een vertrouwde HTTPS-site, genereer/controleer SHA-256 met `Get-FileHash -Algorithm SHA256` en verspreid de verwachte hash onafhankelijk. Onderteken scripts voor distributie bij voorkeur met een organisatiecertificaat (`Set-AuthenticodeSignature`) en valideer de handtekening in het releaseproces. WPS-PowerAddons schakelt execution policy niet uit en voert gedownloade code niet rechtstreeks uit.

## Troubleshooting

- **GUI start niet:** controleer Windows PowerShell 5.1, aanwezigheid van Windows Forms, bestandsrechten en het toepassingslog.
- **UAC geannuleerd:** de hoofdapp blijft open; probeer de tool opnieuw of gebruik alleen-lezencontrole. Er worden geen credentials gevraagd of opgeslagen.
- **Tool wordt niet geladen:** controleer Nederlandse validatiefouten, unieke ID, verplichte properties, relatief scriptpad en bestandspad.
- **Aangepaste tool hash gewijzigd:** wijziging is gedetecteerd; controleer de code en importeer/opslag de tool opnieuw zodat een nieuwe hash wordt geregistreerd.
- **Logmap niet schrijfbaar:** de applicatie gebruikt de lokale `logs\`-map als fallback en logt die situatie.
- **Bootstrap-hash wijkt af:** stop; controleer het pakket en de hash via een onafhankelijk vertrouwd kanaal.

## Bekende beperkingen en Windows-testprocedure

Deze applicatie vereist Windows PowerShell 5.1 en Windows Forms; beheeracties zijn afhankelijk van Windows-versie, netwerkbeleid, SCCM/SAP-installatie en rechten. UAC, services, DISM, SFC, batterijhardware, SAP, Teams-cachepaden en ProgramData-installatie moeten vóór distributie op representatieve Windows 10- en Windows 11-apparaten handmatig worden gecontroleerd. Test daarnaast portable/current-user zonder adminaccount, AllUsers met en zonder UAC-annulering, pakket-hashfout en een ZIP met `../`-pad. De projectvalidatie voert geen reparaties of destructieve tools uit; dit document claimt geen live uitvoering van Windows-herstelacties.
