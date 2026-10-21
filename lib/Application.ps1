function Show-WPSOutputWindow {
    param([string]$Title, [string]$Text)
    $dialog = New-Object Windows.Forms.Form
    $dialog.Text = $Title
    $dialog.Size = New-Object Drawing.Size(760, 520)
    $dialog.StartPosition = 'CenterParent'
    $dialog.MinimumSize = New-Object Drawing.Size(520, 360)
    $box = New-Object Windows.Forms.TextBox
    $box.Multiline = $true
    $box.ReadOnly = $true
    $box.ScrollBars = 'Both'
    $box.WordWrap = $false
    $box.Dock = 'Fill'
    $box.Font = New-Object Drawing.Font('Consolas', 9)
    $box.Text = $Text
    $dialog.Controls.Add($box)
    $dialog.ShowDialog() | Out-Null
    $dialog.Dispose()
}

function Import-WPSApplicationState {
    try {
        $state = Read-WPSConfiguration -RootPath $script:WPSUi.RootPath
        $script:WPSUi.Settings = $state.Settings
        $script:WPSUi.Tools = @($state.Tools)
        $script:WPSUi.LogDirectory = $state.LogDirectory
        $script:WPSUi.ValidationErrors = @($state.Errors)
        foreach ($tool in $script:WPSUi.Tools) {
            $tool.Favourite = ($tool.Id -in $script:WPSUi.Settings.FavouriteToolIds)
        }
    } catch {
        $script:WPSUi.ValidationErrors = @($_.Exception.Message)
        Write-WPSApplicationLog -RootPath $script:WPSUi.RootPath -Level ERROR -Message $_.Exception.Message
        $script:WPSUi.Tools = @()
        if (-not $script:WPSUi.Settings) { $script:WPSUi.Settings = Get-WPSDefaultSettings }
        $script:WPSUi.LogDirectory = Get-WPSLogDirectory -RootPath $script:WPSUi.RootPath -InstallScope $script:WPSUi.Settings.InstallScope
    }
}

function Save-WPSFavouriteState {
    $favourites = @($script:WPSUi.Tools | Where-Object Favourite | Select-Object -ExpandProperty Id)
    $script:WPSUi.Settings.FavouriteToolIds = $favourites
    Save-WPSUserPreferences -Settings $script:WPSUi.Settings
}

function Get-WPSLastExecution {
    param([string]$ToolId)
    $index = Join-Path $script:WPSUi.LogDirectory 'index.json'
    if (-not (Test-Path -LiteralPath $index -PathType Leaf)) { return $null }
    try {
        $data = ConvertFrom-Json -InputObject (Get-Content -LiteralPath $index -Raw -Encoding UTF8)
        $entries = @($data | ForEach-Object { $_ } | Where-Object { -not $ToolId -or $_.ToolId -eq $ToolId })
        return ($entries | Sort-Object Timestamp -Descending | Select-Object -First 1)
    } catch {
        Write-WPSApplicationLog -RootPath $script:WPSUi.RootPath -LogDirectory $script:WPSUi.LogDirectory -Level WARN -Message ('Logindex kon niet worden gelezen: {0}' -f $_.Exception.Message)
        return $null
    }
}

function Get-WPSToolConfirmationDetails {
    param($Tool)
    switch ($Tool.Id) {
        'powershell-command' { return 'De opdracht draait zonder administratorverhoging onder uw huidige account. Opdrachten kunnen bestanden en instellingen wijzigen; gebruik geen opdrachten van onbekende herkomst.' }
        'sap-localgui-repair' { return 'Sluit SAP GUI en Microsoft Excel zelf voordat u doorgaat; WPS-PowerAddons sluit deze programma''s niet.' }
        'teams-cache-cleanup' { return 'Teams moet vooraf handmatig zijn afgesloten. WPS-PowerAddons sluit Teams niet en raakt alleen gedetecteerde cachemappen aan.' }
        'onedrive-reset' { return 'Als OneDrive actief is, vraagt de tool apart toestemming voordat alleen het OneDrive-proces wordt gestopt.' }
        'restart-print-spooler' { return 'Actieve printertaken kunnen worden onderbroken; de Spooler-service wordt herstart.' }
        'reset-winsock' { return 'Netwerkverbindingen kunnen worden beïnvloed; een Windows-herstart kan nodig zijn.' }
        'clear-dns-cache' { return 'Alleen de lokale DNS-resolvercache wordt gewist.' }
        'dism-restorehealth' { return 'De Windows-image kan worden aangepast en een herstart kan nodig zijn.' }
        'system-file-checker' { return 'Windows-systeembestanden kunnen worden gerepareerd; een herstart kan nodig zijn.' }
        'restart-windows-update-services' { return 'Windows Update-services worden herstart; SoftwareDistribution en gebruikersbestanden blijven onaangeroerd.' }
        default { return 'Controleer de toolbeschrijving en sluit alleen applicaties die daarin expliciet worden genoemd. Er worden geen applicaties automatisch gesloten.' }
    }
}

function Show-WPSPowerShellCommandDialog {
    $form = New-Object Windows.Forms.Form
    $form.Text = 'PowerShell-opdracht uitvoeren'
    $form.Size = New-Object Drawing.Size(780, 600)
    $form.MinimumSize = New-Object Drawing.Size(640, 460)
    $form.StartPosition = 'CenterParent'
    $form.FormBorderStyle = 'Sizable'
    $warning = New-Object Windows.Forms.Label
    $warning.Text = 'Voer alleen opdrachten in die u begrijpt en vertrouwt. De opdracht draait als uw huidige gebruiker, zonder UAC-verhoging. Wijzigingen door de opdracht kunnen niet automatisch ongedaan worden gemaakt; interactieve opdrachten worden niet ondersteund. De opdracht en uitvoer worden niet in het logboek opgeslagen.'
    $warning.Dock = 'Top'
    $warning.Height = 74
    $warning.Padding = New-Object Windows.Forms.Padding(12)
    $warning.BackColor = [Drawing.Color]::FromArgb(255, 244, 204)
    $form.Controls.Add($warning)
    $commandBox = New-Object Windows.Forms.TextBox
    $commandBox.Multiline = $true
    $commandBox.AcceptsReturn = $true
    $commandBox.AcceptsTab = $true
    $commandBox.ScrollBars = 'Both'
    $commandBox.WordWrap = $false
    $commandBox.Dock = 'Fill'
    $commandBox.Font = New-Object Drawing.Font('Consolas', 10)
    $commandBox.MaxLength = 50000
    $form.Controls.Add($commandBox)
    $confirmation = New-Object Windows.Forms.CheckBox
    $confirmation.Text = 'Ik heb de opdracht gecontroleerd en wil deze uitvoeren.'
    $confirmation.AutoSize = $true
    $confirmation.Dock = 'Left'
    $confirmation.Padding = New-Object Windows.Forms.Padding(8)
    $buttons = New-Object Windows.Forms.FlowLayoutPanel
    $buttons.Dock = 'Bottom'
    $buttons.Height = 48
    $buttons.FlowDirection = 'RightToLeft'
    $run = New-Object Windows.Forms.Button
    $run.Text = 'Opdracht uitvoeren'
    $run.AutoSize = $true
    $run.Enabled = $false
    $cancel = New-Object Windows.Forms.Button
    $cancel.Text = 'Annuleren'
    $cancel.AutoSize = $true
    $cancel.DialogResult = [Windows.Forms.DialogResult]::Cancel
    $updateRunState = {
        $run.Enabled = $confirmation.Checked -and -not [string]::IsNullOrWhiteSpace($commandBox.Text)
    }.GetNewClosure()
    $confirmation.Add_CheckedChanged($updateRunState)
    $commandBox.Add_TextChanged($updateRunState)
    $run.Add_Click({
        $form.Tag = $commandBox.Text
        $form.DialogResult = [Windows.Forms.DialogResult]::OK
        $form.Close()
    }.GetNewClosure())
    $buttons.Controls.AddRange(@($run, $cancel))
    $form.Controls.Add($buttons)
    $form.Controls.Add($confirmation)
    $form.AcceptButton = $run
    $form.CancelButton = $cancel
    $form.Tag = $null
    $form.ShowDialog($script:WPSUi.Form) | Out-Null
    $selectedCommand = [string]$form.Tag
    $form.Dispose()
    return $selectedCommand
}

function Show-WPSRestartChoice {
    param([string]$Message)
    $form = New-Object Windows.Forms.Form
    $form.Text = 'WPS-PowerAddons - Herstart'
    $form.Size = New-Object Drawing.Size(480, 180)
    $form.StartPosition = 'CenterParent'
    $form.FormBorderStyle = 'FixedDialog'
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false
    $label = New-Object Windows.Forms.Label
    $label.Text = $Message
    $label.Location = New-Object Drawing.Point(18, 18)
    $label.Size = New-Object Drawing.Size(430, 55)
    $form.Controls.Add($label)
    $result = 'Later'
    foreach ($pair in @(@('Nu opnieuw opstarten', 'Now'), @('Later opnieuw opstarten', 'Later'), @('Annuleren', 'Cancel'))) {
        $button = New-Object Windows.Forms.Button
        $button.Text = $pair[0]
        $button.Size = New-Object Drawing.Size(136, 32)
        $button.Location = New-Object Drawing.Point((18 + (($form.Controls.Count - 1) * 142)), 88)
        $value = $pair[1]
        $button.Add_Click({ $script:WPSRestartChoice = $value; $form.Close() }.GetNewClosure())
        $form.Controls.Add($button)
    }
    $script:WPSRestartChoice = 'Later'
    $form.ShowDialog($script:WPSUi.Form) | Out-Null
    $result = $script:WPSRestartChoice
    $form.Dispose()
    if ($result -eq 'Now') {
        $confirm = [Windows.Forms.MessageBox]::Show('De computer wordt nu opnieuw opgestart. Niet-opgeslagen werk kan verloren gaan. Doorgaan?', 'WPS-PowerAddons - Bevestig herstart', [Windows.Forms.MessageBoxButtons]::YesNo, [Windows.Forms.MessageBoxIcon]::Warning, [Windows.Forms.MessageBoxDefaultButton]::Button2)
        if ($confirm -eq [Windows.Forms.DialogResult]::Yes) {
            Start-Process -FilePath shutdown.exe -ArgumentList '/r /t 0' -ErrorAction Stop
        }
    }
}

function Start-WPSAsyncTool {
    param($Tool, [bool]$ReadOnly)
    if ($script:WPSUi.Running.ContainsKey([string]$Tool.Id)) {
        [Windows.Forms.MessageBox]::Show('Deze tool wordt al uitgevoerd.', 'WPS-PowerAddons', 'OK', 'Information') | Out-Null
        return
    }
    $commandText = $null
    if ($Tool.Id -eq 'powershell-command') {
        $commandText = Show-WPSPowerShellCommandDialog
        if ([string]::IsNullOrWhiteSpace($commandText)) { return }
    }
    $adminText = if ($Tool.RequiresAdmin -and -not $ReadOnly) { 'Administratorrechten zijn vereist; Windows toont UAC voor alleen deze tool.' } else { 'Er worden geen administratorrechten gevraagd.' }
    $changeText = if ($ReadOnly) { 'De tool wordt alleen gebruikt om informatie te controleren.' } else { $Tool.Description }
    $restartText = if ($Tool.RestartBehaviour -eq 'None') { 'Een herstart is niet voorzien.' } else { 'Een herstart kan nodig of aanbevolen zijn; deze start nooit automatisch.' }
    if (($Tool.RequiresConfirmation -and $Tool.Id -ne 'powershell-command') -or ($Tool.RequiresAdmin -and $script:WPSUi.Settings.ConfirmAdministratorTools)) {
        $safetyText = Get-WPSToolConfirmationDetails -Tool $Tool
        $message = "Tool: $($Tool.Name)`r`n$changeText`r`n$adminText`r`n$safetyText`r`n$restartText`r`n`r`nDoorgaan?"
        $answer = [Windows.Forms.MessageBox]::Show($message, 'WPS-PowerAddons - Bevestiging', [Windows.Forms.MessageBoxButtons]::YesNo, [Windows.Forms.MessageBoxIcon]::Warning, [Windows.Forms.MessageBoxDefaultButton]::Button2)
        if ($answer -ne [Windows.Forms.DialogResult]::Yes) {
            $result = New-WPSToolResult $Tool 2 'Cancelled' 'De gebruiker heeft de actie geannuleerd.' (Get-Date) (Get-Date) $false
            Write-WPSToolExecutionLog -Result $result -Tool $Tool -LogDirectory $script:WPSUi.LogDirectory
            $script:WPSUi.LastResult = $result
            $script:WPSUi.StatusLabel.Text = ('{0}: geannuleerd' -f $Tool.Name)
            return
        }
    }
    if ($script:WPSUi.Settings.RecentToolIds -notcontains $Tool.Id) {
        $script:WPSUi.Settings.RecentToolIds = @($Tool.Id) + @($script:WPSUi.Settings.RecentToolIds | Select-Object -First 19)
    } else {
        $script:WPSUi.Settings.RecentToolIds = @($Tool.Id) + @($script:WPSUi.Settings.RecentToolIds | Where-Object { $_ -ne $Tool.Id } | Select-Object -First 19)
    }
    try { Save-WPSUserPreferences -Settings $script:WPSUi.Settings }
    catch { Write-WPSApplicationLog -RootPath $script:WPSUi.RootPath -LogDirectory $script:WPSUi.LogDirectory -Level WARN -Message ('Recent tool kon niet worden opgeslagen: {0}' -f $_.Exception.Message) }

    $runspace = [Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace()
    $runspace.Open()
    $powershell = [Management.Automation.PowerShell]::Create()
    $powershell.Runspace = $runspace
    $securityPath = Join-Path $script:WPSUi.RootPath 'lib\Security.ps1'
    $loggingPath = Join-Path $script:WPSUi.RootPath 'lib\Logging.ps1'
    $executionPath = Join-Path $script:WPSUi.RootPath 'lib\ToolExecution.ps1'
    $loadScript = ". '$($securityPath.Replace("'", "''"))'; . '$($loggingPath.Replace("'", "''"))'; . '$($executionPath.Replace("'", "''"))"
    $powershell.AddScript($loadScript).AddStatement().AddCommand('Invoke-WPSPowerAddonTool').
        AddParameter('Tool', $Tool).AddParameter('RootPath', $script:WPSUi.RootPath).
        AddParameter('LogDirectory', $script:WPSUi.LogDirectory).AddParameter('Settings', $script:WPSUi.Settings).
        AddParameter('Confirmed').AddParameter('ReadOnly', $ReadOnly).
        AddParameter('CommandText', $commandText) | Out-Null
    $async = $powershell.BeginInvoke()
    $script:WPSUi.Running[[string]$Tool.Id] = [pscustomobject]@{
        Tool = $Tool; PowerShell = $powershell; Runspace = $runspace; Async = $async; ReadOnly = $ReadOnly
    }
    $script:WPSUi.StatusLabel.Text = ('Bezig: {0} - gestart om {1}' -f $Tool.Name, (Get-Date -Format HH:mm:ss))
    $script:WPSUi.Progress.Visible = $true
    $script:WPSUi.CancelButton.Enabled = $false
    $script:WPSUi.ProgressTimer.Start()
}

function Complete-WPSAsyncTool {
    param([string]$ToolId)
    $entry = $script:WPSUi.Running[$ToolId]
    try {
        $output = $entry.PowerShell.EndInvoke($entry.Async)
        $result = @($output | Where-Object { $_ -is [pscustomobject] } | Select-Object -Last 1)[0]
        if (-not $result) { throw 'De uitvoeringsengine heeft geen resultaat teruggegeven.' }
    } catch {
        $tool = $entry.Tool
        $result = New-WPSToolResult $tool 1 'GeneralError' ('Uitvoeringsfout: {0}' -f $_.Exception.Message) (Get-Date) (Get-Date) $false
        Write-WPSToolExecutionLog -Result $result -Tool $tool -LogDirectory $script:WPSUi.LogDirectory
    } finally {
        $entry.PowerShell.Dispose()
        $entry.Runspace.Dispose()
        $script:WPSUi.Running.Remove($ToolId)
    }
    $script:WPSUi.LastResult = $result
    $script:WPSUi.StatusLabel.Text = ('{0}: {1} (code {2})' -f $result.ToolName, $result.Status, $result.ExitCode)
    $script:WPSUi.Progress.Visible = ($script:WPSUi.Running.Count -gt 0)
    if ($script:WPSUi.Running.Count -eq 0) { $script:WPSUi.ProgressTimer.Stop() }
    if ($result.Output) { Show-WPSOutputWindow -Title ('WPS-PowerAddons - {0}' -f $result.ToolName) -Text $result.Output }
    $message = "{0}`r`nStatus: {1}`r`nExitcode: {2}`r`nDuur: {3} seconden`r`n`r`n{4}" -f $result.ToolName, $result.Status, $result.ExitCode, $result.Duration, $result.Message
    if ($result.LogPath) { $message += "`r`nLog: $($result.LogPath)" }
    $icon = if ($result.ExitCode -in @(0, 5, 6)) { [Windows.Forms.MessageBoxIcon]::Information } else { [Windows.Forms.MessageBoxIcon]::Warning }
    [Windows.Forms.MessageBox]::Show($message, 'WPS-PowerAddons - Resultaat', [Windows.Forms.MessageBoxButtons]::OK, $icon) | Out-Null
    if ($result.ExitCode -in @(5, 6)) { Show-WPSRestartChoice -Message $message }
}

function Get-WPSFilteredTools {
    param([string]$Category = '', [string]$Filter = '')
    $search = $script:WPSUi.SearchBox.Text.Trim()
    $tools = @($script:WPSUi.Tools)
    if ($Filter -eq 'Uitgeschakeld') { $tools = @($tools | Where-Object { -not $_.Enabled }) }
    elseif ($Filter -eq 'Ingeschakeld') { $tools = @($tools | Where-Object Enabled) }
    elseif (-not $script:WPSUi.Settings.ShowDisabledTools) { $tools = @($tools | Where-Object Enabled) }
    if ($Category -and $Category -ne 'Alle tools') { $tools = @($tools | Where-Object Category -eq $Category) }
    if ($script:WPSUi.OnlyNonAdmin.Checked) { $tools = @($tools | Where-Object { -not $_.RequiresAdmin }) }
    if ($script:WPSUi.FavouritesOnly.Checked) { $tools = @($tools | Where-Object Favourite) }
    if ($Filter -eq 'Ingebouwd') { $tools = @($tools | Where-Object Source -eq 'BuiltIn') }
    if ($Filter -eq 'Aangepast') { $tools = @($tools | Where-Object Source -eq 'Custom') }
    if ($Filter -eq 'Administrator tools') { $tools = @($tools | Where-Object RequiresAdmin) }
    if ($search) {
        $tools = @($tools | Where-Object {
            $haystack = '{0} {1} {2} {3} {4}' -f $_.Name, $_.Description, $_.Category, ($_.Tags -join ' '), $_.Id
            $haystack.IndexOf($search, [StringComparison]::CurrentCultureIgnoreCase) -ge 0
        })
    }
    switch ($script:WPSUi.SortBy.SelectedItem) {
        'Categorie' { $tools = @($tools | Sort-Object Category, Name) }
        'Administratorrechten' { $tools = @($tools | Sort-Object RequiresAdmin, Name) }
        'Bron' { $tools = @($tools | Sort-Object Source, Name) }
        'Favoriet' { $tools = @($tools | Sort-Object @{ Expression = 'Favourite'; Descending = $true }, Name) }
        'Laatst gebruikt' {
            $recent = @($script:WPSUi.Settings.RecentToolIds)
            $tools = @($tools | Sort-Object @{ Expression = { $position = $recent.IndexOf($_.Id); if ($position -lt 0) { 9999 } else { $position } }; Descending = $false }, Name)
        }
        default { $tools = @($tools | Sort-Object Name) }
    }
    return $tools
}

function Show-WPSToolDetails {
    param($Tool)
    $form = New-Object Windows.Forms.Form
    $form.Text = ('Toolinformatie - {0}' -f $Tool.Name)
    $form.Size = New-Object Drawing.Size(640, 480)
    $form.StartPosition = 'CenterParent'
    $details = @(
        ('Naam: {0}' -f $Tool.Name)
        ('Tool-ID: {0}' -f $Tool.Id)
        ('Beschrijving: {0}' -f $Tool.Description)
        ('Categorie: {0}' -f $Tool.Category)
        ('Script: {0}' -f $Tool.Script)
        ('Versie: {0}' -f $Tool.Version)
        ('Auteur: {0}' -f $Tool.Author)
        ('Bron: {0}' -f $(if ($Tool.Source -eq 'Custom') { 'Aangepast' } else { 'Ingebouwd' }))
        ('Tags: {0}' -f ($Tool.Tags -join ', '))
        ('Administratorrechten: {0}' -f $(if ($Tool.RequiresAdmin) { 'Vereist' } else { 'Niet vereist' }))
        ('Bevestiging: {0}' -f $Tool.RequiresConfirmation)
        ('Alleen-lezenmodus: {0}' -f $Tool.SupportsReadOnlyMode)
        ('Herstartgedrag: {0}' -f $Tool.RestartBehaviour)
        ('Time-out: {0} seconden' -f $Tool.TimeoutSeconds)
        ('Laatste uitvoering: {0}' -f $(if (Get-WPSLastExecution -ToolId $Tool.Id) { (Get-WPSLastExecution -ToolId $Tool.Id).Timestamp } else { 'niet geregistreerd' }))
        ('Laatste resultaat: {0}' -f $(if ($script:WPSUi.LastResult -and $script:WPSUi.LastResult.ToolId -eq $Tool.Id) { $script:WPSUi.LastResult.Status } elseif (Get-WPSLastExecution -ToolId $Tool.Id) { (Get-WPSLastExecution -ToolId $Tool.Id).Status } else { 'niet beschikbaar' }))
    ) -join [Environment]::NewLine
    $text = New-Object Windows.Forms.TextBox
    $text.Multiline = $true; $text.ReadOnly = $true; $text.Dock = 'Fill'; $text.ScrollBars = 'Vertical'
    $text.Text = $details
    $form.Controls.Add($text)
    $actions = New-Object Windows.Forms.FlowLayoutPanel
    $actions.Dock = 'Bottom'; $actions.Height = 42
    $run = New-Object Windows.Forms.Button; $run.Text = 'Tool uitvoeren'; $run.AutoSize = $true
    $run.Add_Click({ Start-WPSAsyncTool -Tool $Tool -ReadOnly:$false; $form.Close() }.GetNewClosure())
    $actions.Controls.Add($run)
    if ($Tool.SupportsReadOnlyMode) {
        $check = New-Object Windows.Forms.Button; $check.Text = 'Alleen controleren'; $check.AutoSize = $true
        $check.Add_Click({ Start-WPSAsyncTool -Tool $Tool -ReadOnly:$true; $form.Close() }.GetNewClosure())
        $actions.Controls.Add($check)
    }
    $location = New-Object Windows.Forms.Button; $location.Text = 'Scriptlocatie openen'; $location.AutoSize = $true
    $location.Add_Click({
        try {
            $path = Resolve-WPSRelativePath -RelativePath $Tool.Script -RootPath $script:WPSUi.RootPath -RequireExisting
            Start-Process explorer.exe -ArgumentList ('/select,"{0}"' -f $path)
        } catch { [Windows.Forms.MessageBox]::Show($_.Exception.Message, 'WPS-PowerAddons', 'OK', 'Error') | Out-Null }
    }.GetNewClosure())
    $actions.Controls.Add($location)
    $logs = New-Object Windows.Forms.Button; $logs.Text = 'Logboek bekijken'; $logs.AutoSize = $true
    $logs.Add_Click({
        $index = Join-Path $script:WPSUi.LogDirectory 'index.json'
        if (Test-Path -LiteralPath $index) {
            try {
                $data = ConvertFrom-Json -InputObject (Get-Content -LiteralPath $index -Raw -Encoding UTF8)
                $entry = @($data | ForEach-Object { $_ } | Where-Object ToolId -eq $Tool.Id | Select-Object -First 1)
                if ($entry -and (Test-Path -LiteralPath $entry[0].LogPath)) { Start-Process notepad.exe -ArgumentList ('"{0}"' -f $entry[0].LogPath); return }
            } catch { Write-WPSApplicationLog -RootPath $script:WPSUi.RootPath -LogDirectory $script:WPSUi.LogDirectory -Level WARN -Message ('Logindex lezen mislukt: {0}' -f $_.Exception.Message) }
        }
        [Windows.Forms.MessageBox]::Show('Er is nog geen uitvoeringslog voor deze tool.', 'WPS-PowerAddons', 'OK', 'Information') | Out-Null
    }.GetNewClosure())
    $actions.Controls.Add($logs)
    if ($Tool.Source -eq 'Custom') {
        $edit = New-Object Windows.Forms.Button; $edit.Text = 'Bewerken'; $edit.AutoSize = $true
        $edit.Add_Click({ $form.Close(); Show-WPSAddToolDialog -ExistingTool $Tool; Import-WPSApplicationState }.GetNewClosure())
        $actions.Controls.Add($edit)
        $delete = New-Object Windows.Forms.Button; $delete.Text = 'Verwijderen'; $delete.AutoSize = $true
        $delete.Add_Click({
            if ([Windows.Forms.MessageBox]::Show('Aangepaste tool uit de registratie verwijderen?', 'WPS-PowerAddons', 'YesNo', 'Warning', 'Button2') -eq [Windows.Forms.DialogResult]::Yes) {
                $removeScript = [Windows.Forms.MessageBox]::Show('Ook de scriptmap verwijderen? Logbestanden blijven behouden.', 'WPS-PowerAddons', 'YesNo', 'Warning', 'Button2') -eq [Windows.Forms.DialogResult]::Yes
                try { Remove-WPSCustomTool -Tool $Tool -RootPath $script:WPSUi.RootPath -DeleteScript:$removeScript; $form.Close(); Import-WPSApplicationState }
                catch { [Windows.Forms.MessageBox]::Show($_.Exception.Message, 'WPS-PowerAddons', 'OK', 'Error') | Out-Null }
            }
        }.GetNewClosure())
        $actions.Controls.Add($delete)
    }
    $form.Controls.Add($actions)
    $form.ShowDialog($script:WPSUi.Form) | Out-Null
    $form.Dispose()
}

function Show-WPSToolList {
    param([string]$Category = '', [string]$Filter = '')
    $ui = $script:WPSUi
    $script:WPSUi.PageTitle.Text = if ($Category) { $Category } else { 'Alle tools' }
    $panel = $script:WPSUi.Content
    $panel.SuspendLayout()
    $panel.Controls.Clear()
    $toolbar = New-Object Windows.Forms.FlowLayoutPanel
    $toolbar.Dock = 'Top'; $toolbar.Height = 42; $toolbar.WrapContents = $false; $toolbar.AutoScroll = $true
    $script:WPSUi.OnlyNonAdmin = New-Object Windows.Forms.CheckBox
    $script:WPSUi.OnlyNonAdmin.Text = 'Alleen tools zonder administratorrechten'
    $script:WPSUi.OnlyNonAdmin.AutoSize = $true
    $script:WPSUi.FavouritesOnly = New-Object Windows.Forms.CheckBox
    $script:WPSUi.FavouritesOnly.Text = 'Favorieten'
    $script:WPSUi.FavouritesOnly.AutoSize = $true
    $script:WPSUi.ToolFilter = New-Object Windows.Forms.ComboBox
    $script:WPSUi.ToolFilter.DropDownStyle = 'DropDownList'
    [void]$script:WPSUi.ToolFilter.Items.AddRange(@('Alle', 'Administrator tools', 'Ingebouwd', 'Aangepast', 'Ingeschakeld', 'Uitgeschakeld'))
    $script:WPSUi.ToolFilter.SelectedItem = 'Alle'
    $script:WPSUi.CategoryFilter = New-Object Windows.Forms.ComboBox
    $script:WPSUi.CategoryFilter.DropDownStyle = 'DropDownList'
    [void]$script:WPSUi.CategoryFilter.Items.Add('Alle categorieën')
    foreach ($name in @($script:WPSUi.Tools | Select-Object -ExpandProperty Category -Unique | Sort-Object)) { [void]$script:WPSUi.CategoryFilter.Items.Add($name) }
    if ($Category -and $script:WPSUi.CategoryFilter.Items.Contains($Category)) { $script:WPSUi.CategoryFilter.SelectedItem = $Category }
    else { $script:WPSUi.CategoryFilter.SelectedIndex = 0 }
    $filterLabel = New-Object Windows.Forms.Label
    $filterLabel.Text = 'Filter:'; $filterLabel.AutoSize = $true; $filterLabel.Padding = New-Object Windows.Forms.Padding(8, 8, 0, 0)
    $categoryLabel = New-Object Windows.Forms.Label
    $categoryLabel.Text = 'Categorie:'; $categoryLabel.AutoSize = $true; $categoryLabel.Padding = New-Object Windows.Forms.Padding(8, 8, 0, 0)
    $script:WPSUi.ViewMode = New-Object Windows.Forms.ComboBox
    $script:WPSUi.ViewMode.DropDownStyle = 'DropDownList'
    [void]$script:WPSUi.ViewMode.Items.AddRange(@('Kaarten', 'Compacte lijst'))
    $script:WPSUi.ViewMode.SelectedItem = if ($script:WPSUi.Settings.DefaultView -eq 'List') { 'Compacte lijst' } else { 'Kaarten' }
    $script:WPSUi.SortBy = New-Object Windows.Forms.ComboBox
    $script:WPSUi.SortBy.DropDownStyle = 'DropDownList'
    [void]$script:WPSUi.SortBy.Items.AddRange(@('Naam', 'Categorie', 'Administratorrechten', 'Laatst gebruikt', 'Bron', 'Favoriet'))
    $script:WPSUi.SortBy.SelectedItem = 'Naam'
    $sortLabel = New-Object Windows.Forms.Label
    $sortLabel.Text = 'Sorteren:'; $sortLabel.AutoSize = $true; $sortLabel.Padding = New-Object Windows.Forms.Padding(8, 8, 0, 0)
    $viewLabel = New-Object Windows.Forms.Label; $viewLabel.Text = 'Weergave:'; $viewLabel.AutoSize = $true; $viewLabel.Padding = New-Object Windows.Forms.Padding(8, 8, 0, 0)
    $toolbar.Controls.AddRange(@($script:WPSUi.OnlyNonAdmin, $script:WPSUi.FavouritesOnly, $categoryLabel, $script:WPSUi.CategoryFilter, $filterLabel, $script:WPSUi.ToolFilter, $sortLabel, $script:WPSUi.SortBy, $viewLabel, $script:WPSUi.ViewMode))
    $panel.Controls.Add($toolbar)
    $flow = New-Object Windows.Forms.FlowLayoutPanel
    $flow.Dock = 'Fill'; $flow.AutoScroll = $true; $flow.WrapContents = $true; $flow.Padding = New-Object Windows.Forms.Padding(10)
    $panel.Controls.Add($flow)
    $render = {
        $flow.Controls.Clear()
        $activeFilter = [string]$ui.ToolFilter.SelectedItem
        $activeCategory = $Category
        if ($ui.CategoryFilter.SelectedIndex -gt 0) { $activeCategory = [string]$ui.CategoryFilter.SelectedItem }
        $tools = Get-WPSFilteredTools -Category $activeCategory -Filter $activeFilter
        foreach ($tool in $tools) {
            $card = New-Object Windows.Forms.Panel
            $compact = ($ui.ViewMode.SelectedItem -eq 'Compacte lijst')
            $card.Width = if ($compact) { 790 } else { 300 }
            $card.Height = if ($compact) { 74 } else { 168 }
            $card.Margin = New-Object Windows.Forms.Padding(8)
            $card.BackColor = [Drawing.Color]::White
            $label = New-Object Windows.Forms.Label
            $badge = if ($tool.RequiresAdmin) { '🛡 Administratorrechten vereist' } else { 'Geen administratorrechten nodig' }
            $label.Text = "$($tool.Name)`r`n$($tool.Category)  |  $($tool.Version)  |  $badge`r`n$($tool.Description)  |  Bron: $(if ($tool.Source -eq 'Custom') { 'Aangepast' } else { 'Ingebouwd' })"
            $label.Location = New-Object Drawing.Point(10, 8)
            $label.Size = if ($compact) { New-Object Drawing.Size(470, 58) } else { New-Object Drawing.Size(280, 94) }
            $label.Font = New-Object Drawing.Font('Segoe UI', 9)
            $card.Controls.Add($label)
            $run = New-Object Windows.Forms.Button
            $run.Text = 'Uitvoeren'; $run.Location = if ($compact) { New-Object Drawing.Point(480, 20) } else { New-Object Drawing.Point(8, 118) }; $run.Size = New-Object Drawing.Size(82, 30)
            $toolCopy = $tool
            $run.Add_Click({ Start-WPSAsyncTool -Tool $toolCopy -ReadOnly:$false }.GetNewClosure())
            $card.Controls.Add($run)
            $info = New-Object Windows.Forms.Button
            $info.Text = 'Info'; $info.Location = if ($compact) { New-Object Drawing.Point(568, 20) } else { New-Object Drawing.Point(96, 118) }; $info.Size = New-Object Drawing.Size(55, 30)
            $info.Add_Click({ Show-WPSToolDetails -Tool $toolCopy }.GetNewClosure())
            $card.Controls.Add($info)
            $fav = New-Object Windows.Forms.Button
            $fav.Text = if ($tool.Favourite) { '★' } else { '☆' }
            $fav.Location = if ($compact) { New-Object Drawing.Point(629, 20) } else { New-Object Drawing.Point(157, 118) }; $fav.Size = New-Object Drawing.Size(42, 30)
            $fav.Add_Click({
                $toolCopy.Favourite = -not $toolCopy.Favourite
                try { Save-WPSFavouriteState; Show-WPSToolList -Category $Category -Filter $activeFilter }
                catch { [Windows.Forms.MessageBox]::Show($_.Exception.Message, 'WPS-PowerAddons', 'OK', 'Error') | Out-Null }
            }.GetNewClosure())
            $card.Controls.Add($fav)
            if ($tool.SupportsReadOnlyMode) {
                $check = New-Object Windows.Forms.Button
                $check.Text = 'Alleen controleren'; $check.Location = if ($compact) { New-Object Drawing.Point(677, 20) } else { New-Object Drawing.Point(205, 118) }; $check.Size = New-Object Drawing.Size(106, 30)
                $check.Add_Click({ Start-WPSAsyncTool -Tool $toolCopy -ReadOnly:$true }.GetNewClosure())
                $card.Controls.Add($check)
            }
            $flow.Controls.Add($card)
        }
        if ($tools.Count -eq 0) {
            $empty = New-Object Windows.Forms.Label
            $empty.Text = 'Geen tools gevonden. Pas de filters aan of vernieuw de configuratie.'
            $empty.AutoSize = $true; $flow.Controls.Add($empty)
        }
    }.GetNewClosure()
    $script:WPSUi.CategoryFilter.Add_SelectedIndexChanged($render)
    $script:WPSUi.OnlyNonAdmin.Add_CheckedChanged($render)
    $script:WPSUi.FavouritesOnly.Add_CheckedChanged($render)
    $script:WPSUi.ToolFilter.Add_SelectedIndexChanged($render)
    $script:WPSUi.ViewMode.Add_SelectedIndexChanged($render)
    $script:WPSUi.SortBy.Add_SelectedIndexChanged($render)
    $script:WPSUi.SearchBox.Add_TextChanged($render)
    & $render
    $panel.ResumeLayout()
}

function Show-WPSDashboard {
    $script:WPSUi.PageTitle.Text = 'Dashboard'
    $panel = $script:WPSUi.Content
    $panel.Controls.Clear()
    $enabled = @($script:WPSUi.Tools | Where-Object Enabled)
    $cards = @(
        @('Ingeschakelde tools', [string]$enabled.Count)
        @('Zonder administratorrechten', [string]@($enabled | Where-Object { -not $_.RequiresAdmin }).Count)
        @('Administratorrechten vereist', [string]@($enabled | Where-Object RequiresAdmin).Count)
        @('Aangepaste tools', [string]@($enabled | Where-Object Source -eq 'Custom').Count)
    )
    $flow = New-Object Windows.Forms.FlowLayoutPanel
    $flow.Dock = 'Fill'; $flow.AutoScroll = $true; $flow.Padding = New-Object Windows.Forms.Padding(18)
    $panel.Controls.Add($flow)
    foreach ($item in $cards) {
        $card = New-Object Windows.Forms.Panel
        $card.Size = New-Object Drawing.Size(230, 95); $card.Margin = New-Object Windows.Forms.Padding(10); $card.BackColor = [Drawing.Color]::White
        $label = New-Object Windows.Forms.Label
        $label.Text = $item[0]; $label.Location = New-Object Drawing.Point(12, 12); $label.AutoSize = $true
        $count = New-Object Windows.Forms.Label
        $count.Text = $item[1]; $count.Location = New-Object Drawing.Point(12, 42); $count.Font = New-Object Drawing.Font('Segoe UI', 18, [Drawing.FontStyle]::Bold); $count.AutoSize = $true
        $card.Controls.AddRange(@($label, $count)); $flow.Controls.Add($card)
    }
    $status = New-Object Windows.Forms.Label
    $status.AutoSize = $true; $status.Margin = New-Object Windows.Forms.Padding(16)
    $lastExecution = Get-WPSLastExecution
    if ($script:WPSUi.LastResult) {
        $status.Text = ('Meest recent: {0} - {1}' -f $script:WPSUi.LastResult.ToolName, $script:WPSUi.LastResult.Status)
    } elseif ($lastExecution) {
        $status.Text = ('Meest recent: {0} - {1} ({2})' -f $lastExecution.ToolName, $lastExecution.Status, $lastExecution.Timestamp)
    } else { $status.Text = 'Meest recent: nog geen tool uitgevoerd.' }
    $flow.Controls.Add($status)
    $favTitle = New-Object Windows.Forms.Label
    $favTitle.Text = 'Veelgebruikte tools / Favorieten'; $favTitle.AutoSize = $true; $favTitle.Margin = New-Object Windows.Forms.Padding(16)
    $flow.Controls.Add($favTitle)
    foreach ($tool in @($enabled | Where-Object Favourite | Select-Object -First 6)) {
        $button = New-Object Windows.Forms.Button
        $button.Text = $tool.Name; $button.Size = New-Object Drawing.Size(300, 42)
        $toolCopy = $tool
        $button.Add_Click({ Start-WPSAsyncTool -Tool $toolCopy -ReadOnly:$false }.GetNewClosure())
        $flow.Controls.Add($button)
    }
    $recentTitle = New-Object Windows.Forms.Label
    $recentTitle.Text = 'Recent gebruikt'; $recentTitle.AutoSize = $true; $recentTitle.Margin = New-Object Windows.Forms.Padding(16)
    $flow.Controls.Add($recentTitle)
    foreach ($recentId in @($script:WPSUi.Settings.RecentToolIds | Select-Object -First 5)) {
        $recentTool = $enabled | Where-Object Id -eq $recentId | Select-Object -First 1
        if ($recentTool) {
            $button = New-Object Windows.Forms.Button
            $button.Text = $recentTool.Name; $button.Size = New-Object Drawing.Size(300, 42)
            $toolCopy = $recentTool
            $button.Add_Click({ Start-WPSAsyncTool -Tool $toolCopy -ReadOnly:$false }.GetNewClosure())
            $flow.Controls.Add($button)
        }
    }
}

function Show-WPSLogPage {
    $script:WPSUi.PageTitle.Text = 'Logboeken'
    $panel = $script:WPSUi.Content; $panel.Controls.Clear()
    $toolbar = New-Object Windows.Forms.FlowLayoutPanel
    $toolbar.Dock = 'Top'; $toolbar.Height = 76; $toolbar.WrapContents = $true; $toolbar.AutoScroll = $true
    $openFolder = New-Object Windows.Forms.Button; $openFolder.Text = 'Logmap openen'; $openFolder.AutoSize = $true
    $openFolder.Add_Click({ Start-Process explorer.exe -ArgumentList ('"{0}"' -f $script:WPSUi.LogDirectory) })
    $toolFilter = New-Object Windows.Forms.ComboBox; $toolFilter.DropDownStyle = 'DropDownList'; $toolFilter.Width = 150
    [void]$toolFilter.Items.Add('Alle tools')
    foreach ($name in @($script:WPSUi.Tools | Select-Object -ExpandProperty Name -Unique | Sort-Object)) { [void]$toolFilter.Items.Add($name) }
    $toolFilter.SelectedIndex = 0
    $resultFilter = New-Object Windows.Forms.ComboBox; $resultFilter.DropDownStyle = 'DropDownList'; $resultFilter.Width = 145
    [void]$resultFilter.Items.AddRange(@('Alle resultaten', 'Success', 'Cancelled', 'RestartRecommended', 'RestartRequired', 'GeneralError', 'AdministratorRightsUnavailable', 'PrerequisiteMissing', 'Timeout', 'ValidationFailed', 'ScriptHashChanged'))
    $resultFilter.SelectedIndex = 0
    $dateFilter = New-Object Windows.Forms.DateTimePicker; $dateFilter.ShowCheckBox = $true; $dateFilter.Checked = $false; $dateFilter.Width = 125
    $clean = New-Object Windows.Forms.Button; $clean.Text = 'Oude logboeken verwijderen'; $clean.AutoSize = $true
    $clean.Add_Click({
        $answer = [Windows.Forms.MessageBox]::Show('Logbestanden ouder dan de bewaartermijn permanent verwijderen?', 'WPS-PowerAddons - Bevestigen', 'YesNo', 'Warning', 'Button2')
        if ($answer -eq [Windows.Forms.DialogResult]::Yes) {
            $cutoff = (Get-Date).AddDays(-$script:WPSUi.Settings.LogRetentionDays)
            Get-ChildItem -LiteralPath $script:WPSUi.LogDirectory -File -ErrorAction SilentlyContinue |
                Where-Object { $_.LastWriteTime -lt $cutoff -and $_.Name -ne 'index.json' } |
                Remove-Item -Force -ErrorAction Stop
            $indexPath = Join-Path $script:WPSUi.LogDirectory 'index.json'
            if (Test-Path -LiteralPath $indexPath) {
                $entries = @(ConvertFrom-Json -InputObject (Get-Content -LiteralPath $indexPath -Raw -Encoding UTF8) | ForEach-Object { $_ })
                $remaining = @($entries | Where-Object { Test-Path -LiteralPath $_.LogPath -PathType Leaf })
                Save-WPSJsonAtomic -Value $remaining -Path $indexPath
            }
            Show-WPSLogPage
        }
    })
    $export = New-Object Windows.Forms.Button; $export.Text = 'Selectie exporteren als ZIP'; $export.AutoSize = $true
    $toolbar.Controls.AddRange(@($openFolder, $toolFilter, $resultFilter, $dateFilter, $clean, $export)); $panel.Controls.Add($toolbar)
    $grid = New-Object Windows.Forms.DataGridView
    $grid.Dock = 'Fill'; $grid.ReadOnly = $true; $grid.AllowUserToAddRows = $false; $grid.AutoSizeColumnsMode = 'Fill'
    $grid.SelectionMode = 'FullRowSelect'; $grid.MultiSelect = $true
    [void]$grid.Columns.Add('Timestamp', 'Datum')
    [void]$grid.Columns.Add('ToolName', 'Tool')
    [void]$grid.Columns.Add('Status', 'Resultaat')
    [void]$grid.Columns.Add('LogPath', 'Logbestand')
    $index = Join-Path $script:WPSUi.LogDirectory 'index.json'
    $logEntries = @()
    if (Test-Path -LiteralPath $index -PathType Leaf) {
        try {
            $entryData = ConvertFrom-Json -InputObject (Get-Content -LiteralPath $index -Raw -Encoding UTF8)
            $logEntries = @($entryData | ForEach-Object { $_ })
        } catch { Write-WPSApplicationLog -RootPath $script:WPSUi.RootPath -LogDirectory $script:WPSUi.LogDirectory -Level ERROR -Message $_.Exception.Message }
    }
    $renderLogs = {
        $grid.Rows.Clear()
        foreach ($entry in $logEntries) {
            if ($toolFilter.SelectedIndex -gt 0 -and $entry.ToolName -ne $toolFilter.SelectedItem) { continue }
            if ($resultFilter.SelectedIndex -gt 0 -and $entry.Status -ne $resultFilter.SelectedItem) { continue }
            if ($dateFilter.Checked) {
                $timestamp = [DateTime]::MinValue
                if (-not [DateTime]::TryParse([string]$entry.Timestamp, [ref]$timestamp) -or $timestamp.Date -ne $dateFilter.Value.Date) { continue }
            }
            [void]$grid.Rows.Add($entry.Timestamp, $entry.ToolName, $entry.Status, $entry.LogPath)
        }
    }.GetNewClosure()
    $toolFilter.Add_SelectedIndexChanged($renderLogs)
    $resultFilter.Add_SelectedIndexChanged($renderLogs)
    $dateFilter.Add_ValueChanged($renderLogs)
    & $renderLogs
    $grid.Add_CellDoubleClick({
        if ($grid.SelectedRows.Count -gt 0) {
            $path = [string]$grid.SelectedRows[0].Cells['LogPath'].Value
            if (Test-Path -LiteralPath $path -PathType Leaf) { Start-Process notepad.exe -ArgumentList ('"{0}"' -f $path) }
        }
    }.GetNewClosure())
    $export.Add_Click({
        if ($grid.SelectedRows.Count -eq 0) { return }
        $saveDialog = New-Object Windows.Forms.SaveFileDialog; $saveDialog.Filter = 'ZIP-bestand (*.zip)|*.zip'; $saveDialog.FileName = ('WPS-PowerAddons-logs-{0}.zip' -f (Get-Date -Format yyyyMMdd-HHmmss))
        if ($saveDialog.ShowDialog($script:WPSUi.Form) -eq [Windows.Forms.DialogResult]::OK) {
            $temporary = Join-Path $env:TEMP ('WPS-PowerAddons-logexport-{0}' -f [Guid]::NewGuid().ToString('N'))
            try {
                New-Item -ItemType Directory -Path $temporary | Out-Null
                foreach ($row in $grid.SelectedRows) {
                    $path = [string]$row.Cells['LogPath'].Value
                    if (Test-Path -LiteralPath $path -PathType Leaf) { Copy-Item -LiteralPath $path -Destination $temporary }
                }
                if (@(Get-ChildItem -LiteralPath $temporary -File).Count -eq 0) { throw 'De selectie bevat geen bestaande logbestanden.' }
                Add-Type -AssemblyName System.IO.Compression.FileSystem
                if (Test-Path -LiteralPath $saveDialog.FileName) { Remove-Item -LiteralPath $saveDialog.FileName -Force }
                [IO.Compression.ZipFile]::CreateFromDirectory($temporary, $saveDialog.FileName)
            } catch { [Windows.Forms.MessageBox]::Show($_.Exception.Message, 'WPS-PowerAddons', 'OK', 'Error') | Out-Null }
            finally { if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Recurse -Force -ErrorAction SilentlyContinue } }
        }
        $saveDialog.Dispose()
    }.GetNewClosure())
    $panel.Controls.Add($grid)
}

function Show-WPSSettingsPage {
    $script:WPSUi.PageTitle.Text = 'Instellingen'
    $panel = $script:WPSUi.Content; $panel.Controls.Clear()
    $form = New-Object Windows.Forms.FlowLayoutPanel
    $form.Dock = 'Fill'; $form.FlowDirection = 'TopDown'; $form.WrapContents = $false; $form.AutoScroll = $true; $form.Padding = New-Object Windows.Forms.Padding(18)
    $panel.Controls.Add($form)
    $retentionLabel = New-Object Windows.Forms.Label; $retentionLabel.Text = 'Logretentie in dagen (1-3650)'; $retentionLabel.AutoSize = $true
    $retention = New-Object Windows.Forms.NumericUpDown; $retention.Minimum = 1; $retention.Maximum = 3650; $retention.Value = $script:WPSUi.Settings.LogRetentionDays
    $timeoutLabel = New-Object Windows.Forms.Label; $timeoutLabel.Text = 'Standaard time-out in seconden (10-7200)'; $timeoutLabel.AutoSize = $true
    $timeout = New-Object Windows.Forms.NumericUpDown; $timeout.Minimum = 10; $timeout.Maximum = 7200; $timeout.Value = $script:WPSUi.Settings.DefaultTimeoutSeconds
    $viewLabel = New-Object Windows.Forms.Label; $viewLabel.Text = 'Standaardweergave'; $viewLabel.AutoSize = $true
    $view = New-Object Windows.Forms.ComboBox; $view.DropDownStyle = 'DropDownList'
    [void]$view.Items.AddRange(@('Kaarten', 'Compacte lijst'))
    $view.SelectedItem = if ($script:WPSUi.Settings.DefaultView -eq 'List') { 'Compacte lijst' } else { 'Kaarten' }
    $editorLabel = New-Object Windows.Forms.Label; $editorLabel.Text = 'Voorkeurseditor'; $editorLabel.AutoSize = $true
    $editor = New-Object Windows.Forms.TextBox; $editor.Width = 300; $editor.Text = $script:WPSUi.Settings.PreferredEditor
    $scope = New-Object Windows.Forms.Label; $scope.Text = ('Installatiescope (beheerd door bootstrap): {0}' -f $script:WPSUi.Settings.InstallScope); $scope.AutoSize = $true
    $checks = @()
    foreach ($property in @('ConfirmAdministratorTools', 'CheckCustomToolHashes', 'ShowDisabledTools', 'EnableToolTimeout')) {
        $check = New-Object Windows.Forms.CheckBox
        $check.Text = $property; $check.Checked = [bool]$script:WPSUi.Settings.$property; $check.AutoSize = $true
        $checks += $check
    }
    $buttons = New-Object Windows.Forms.FlowLayoutPanel; $buttons.AutoSize = $true
    $save = New-Object Windows.Forms.Button; $save.Text = 'Opslaan'; $save.AutoSize = $true
    $save.Add_Click({
        $newSettings = $script:WPSUi.Settings | Select-Object *
        $newSettings.LogRetentionDays = [int]$retention.Value
        $newSettings.DefaultTimeoutSeconds = [int]$timeout.Value
        $newSettings.DefaultView = if ($view.SelectedItem -eq 'Compacte lijst') { 'List' } else { 'Cards' }
        $newSettings.PreferredEditor = $editor.Text.Trim()
        for ($i = 0; $i -lt $checks.Count; $i++) { $newSettings.($checks[$i].Text) = $checks[$i].Checked }
        $validation = Test-WPSSettings -Settings $newSettings
        if (-not $validation.Valid) { [Windows.Forms.MessageBox]::Show(($validation.Errors -join "`r`n"), 'WPS-PowerAddons - Validatie', 'OK', 'Error') | Out-Null; return }
        try {
            $fileSettings = $newSettings | Select-Object *
            $fileSettings.FavouriteToolIds = @()
            $fileSettings.RecentToolIds = @()
            Save-WPSJsonAtomic -Value $fileSettings -Path (Join-Path $script:WPSUi.RootPath 'config\settings.json') -Backup
            $script:WPSUi.Settings = $newSettings
            [Windows.Forms.MessageBox]::Show('Instellingen opgeslagen.', 'WPS-PowerAddons', 'OK', 'Information') | Out-Null
        } catch { [Windows.Forms.MessageBox]::Show($_.Exception.Message, 'WPS-PowerAddons', 'OK', 'Error') | Out-Null }
    }.GetNewClosure())
    $reset = New-Object Windows.Forms.Button; $reset.Text = 'Standaardinstellingen herstellen'; $reset.AutoSize = $true
    $reset.Add_Click({
        $answer = [Windows.Forms.MessageBox]::Show('Standaardinstellingen herstellen?', 'WPS-PowerAddons - Bevestigen', 'YesNo', 'Warning', 'Button2')
        if ($answer -eq [Windows.Forms.DialogResult]::Yes) {
            $defaults = Get-WPSDefaultSettings
            $defaults.InstallScope = $script:WPSUi.Settings.InstallScope
            $defaults.FavouriteToolIds = @()
            $defaults.RecentToolIds = @()
            Save-WPSJsonAtomic -Value $defaults -Path (Join-Path $script:WPSUi.RootPath 'config\settings.json') -Backup
            $script:WPSUi.Settings = $defaults
            Show-WPSSettingsPage
        }
    })
    $buttons.Controls.AddRange(@($save, $reset))
    foreach ($control in @($retentionLabel, $retention, $timeoutLabel, $timeout, $viewLabel, $view, $editorLabel, $editor, $scope) + $checks + @($buttons)) { $form.Controls.Add($control) }
    foreach ($pair in @(
        @('Logmap openen', $script:WPSUi.LogDirectory)
        @('Configuratiemap openen', (Join-Path $script:WPSUi.RootPath 'config'))
        @('Aangepaste tools openen', (Join-Path $script:WPSUi.RootPath 'custom-tools'))
    )) {
        $button = New-Object Windows.Forms.Button; $button.Text = $pair[0]; $button.AutoSize = $true
        $path = $pair[1]
        $button.Add_Click({ Start-Process explorer.exe -ArgumentList ('"{0}"' -f $path) }.GetNewClosure())
        $form.Controls.Add($button)
    }
}

function Show-WPSAddToolDialog {
    param($ExistingTool)
    $dialog = New-Object Windows.Forms.Form
    $dialog.Text = if ($ExistingTool) { 'Aangepaste tool bewerken' } else { 'Tool toevoegen' }
    $dialog.Size = New-Object Drawing.Size(660, 650)
    $dialog.StartPosition = 'CenterParent'
    $dialog.AutoScroll = $true
    $layout = New-Object Windows.Forms.TableLayoutPanel
    $layout.Dock = 'Fill'; $layout.ColumnCount = 2; $layout.AutoSize = $true; $layout.Padding = New-Object Windows.Forms.Padding(12)
    $layout.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('Absolute', 190)))
    $layout.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('Percent', 100)))
    $fields = @{}
    $spec = @(
        @('Toolnaam', 'Name', 'textbox'), @('Unieke tool-ID', 'Id', 'textbox'), @('Categorie', 'Category', 'textbox'),
        @('Beschrijving', 'Description', 'textbox'), @('Scriptbestand', 'Script', 'file'),
        @('Versie', 'Version', 'textbox'), @('Auteur', 'Author', 'textbox'), @('Tags (komma-gescheiden)', 'Tags', 'textbox'),
        @('Icoonlabel (optioneel)', 'Icon', 'textbox'),
        @('Time-out (10-7200)', 'TimeoutSeconds', 'number'), @('Herstartgedrag', 'RestartBehaviour', 'combo')
    )
    foreach ($entry in $spec) {
        $label = New-Object Windows.Forms.Label; $label.Text = $entry[0]; $label.AutoSize = $true; $label.Anchor = 'Left'
        $row = $layout.RowCount; $layout.RowCount++
        $layout.Controls.Add($label, 0, $row)
        if ($entry[2] -eq 'file') {
            $container = New-Object Windows.Forms.FlowLayoutPanel; $container.Dock = 'Fill'
            $fields[$entry[1]] = New-Object Windows.Forms.TextBox; $fields[$entry[1]].Width = 290
            $browse = New-Object Windows.Forms.Button; $browse.Text = 'Script selecteren'
            $browse.Add_Click({
                $picker = New-Object Windows.Forms.OpenFileDialog
                $picker.Filter = 'PowerShell scripts (*.ps1)|*.ps1'
                if ($picker.ShowDialog($dialog) -eq [Windows.Forms.DialogResult]::OK) { $fields['Script'].Text = $picker.FileName }
                $picker.Dispose()
            }.GetNewClosure())
            $container.Controls.AddRange(@($fields[$entry[1]], $browse)); $layout.Controls.Add($container, 1, $row)
        } elseif ($entry[2] -eq 'number') {
            $fields[$entry[1]] = New-Object Windows.Forms.NumericUpDown
            $fields[$entry[1]].Minimum = 10; $fields[$entry[1]].Maximum = 7200; $fields[$entry[1]].Value = 300
            $layout.Controls.Add($fields[$entry[1]], 1, $row)
        } elseif ($entry[2] -eq 'combo') {
            $fields[$entry[1]] = New-Object Windows.Forms.ComboBox
            $fields[$entry[1]].DropDownStyle = 'DropDownList'
            [void]$fields[$entry[1]].Items.AddRange(@('None', 'Recommended', 'Required'))
            $fields[$entry[1]].SelectedItem = 'None'
            $layout.Controls.Add($fields[$entry[1]], 1, $row)
        } else {
            $fields[$entry[1]] = New-Object Windows.Forms.TextBox
            if ($entry[1] -eq 'Description') { $fields[$entry[1]].Multiline = $true; $fields[$entry[1]].Height = 54 }
            $layout.Controls.Add($fields[$entry[1]], 1, $row)
        }
    }
    $checks = @{}
    foreach ($pair in @(@('Administratorrechten vereist', 'RequiresAdmin'), @('Bevestiging vereist', 'RequiresConfirmation'), @('Alleen-lezenmodus beschikbaar', 'SupportsReadOnlyMode'), @('Ingeschakeld', 'Enabled'), @('Favoriet', 'Favourite'))) {
        $check = New-Object Windows.Forms.CheckBox; $check.Text = $pair[0]; $check.AutoSize = $true
        if ($pair[1] -eq 'Enabled') { $check.Checked = $true }
        $checks[$pair[1]] = $check
        $row = $layout.RowCount; $layout.RowCount++
        $layout.Controls.Add((New-Object Windows.Forms.Label), 0, $row); $layout.Controls.Add($check, 1, $row)
    }
    if ($ExistingTool) {
        foreach ($property in @('Name', 'Id', 'Category', 'Description', 'Version', 'Author')) { $fields[$property].Text = [string]$ExistingTool.$property }
        $fields.Tags.Text = @($ExistingTool.Tags) -join ', '
        if ($null -ne $fields.Icon -and $null -ne $ExistingTool.PSObject.Properties['Icon']) { $fields.Icon.Text = [string]$ExistingTool.Icon }
        $fields.TimeoutSeconds.Value = [Math]::Min(7200, [Math]::Max(10, [int]$ExistingTool.TimeoutSeconds))
        $fields.RestartBehaviour.SelectedItem = $ExistingTool.RestartBehaviour
        $fields.Script.Text = Resolve-WPSRelativePath -RelativePath $ExistingTool.Script -RootPath $script:WPSUi.RootPath -RequireExisting
        foreach ($property in @('RequiresAdmin', 'RequiresConfirmation', 'SupportsReadOnlyMode', 'Enabled', 'Favourite')) {
            $checks[$property].Checked = [bool]$ExistingTool.$property
        }
    }
    $buttons = New-Object Windows.Forms.FlowLayoutPanel; $buttons.AutoSize = $true
    $save = New-Object Windows.Forms.Button; $save.Text = if ($ExistingTool) { 'Wijzigingen opslaan' } else { 'Opslaan' }; $save.AutoSize = $true
    $cancel = New-Object Windows.Forms.Button; $cancel.Text = 'Annuleren'; $cancel.AutoSize = $true
    $cancel.Add_Click({ $dialog.Close() }.GetNewClosure())
    $newScript = New-Object Windows.Forms.Button; $newScript.Text = 'Nieuw script maken'; $newScript.AutoSize = $true
    $newScript.Add_Click({
        try {
            if (-not $fields.Name.Text -or -not (Test-WPSToolId $fields.Id.Text)) { throw 'Vul eerst een toolnaam en geldige tool-ID in.' }
            $path = New-WPSCustomToolFromTemplate -Name $fields.Name.Text -Id $fields.Id.Text -RootPath $script:WPSUi.RootPath -Editor $script:WPSUi.Settings.PreferredEditor
            $fields.Script.Text = $path
            if (-not $fields.Description.Text) { $fields.Description.Text = 'Aangepaste PowerShell-supporttool.' }
        } catch { [Windows.Forms.MessageBox]::Show($_.Exception.Message, 'WPS-PowerAddons', 'OK', 'Error') | Out-Null }
    }.GetNewClosure())
    $example = New-Object Windows.Forms.Button; $example.Text = 'Voorbeeldscript openen'; $example.AutoSize = $true
    $example.Add_Click({
        try { Start-Process -FilePath $script:WPSUi.Settings.PreferredEditor -ArgumentList ('"{0}"' -f (Join-Path $script:WPSUi.RootPath 'templates\Example-Tool.ps1')) -ErrorAction Stop }
        catch { [Windows.Forms.MessageBox]::Show($_.Exception.Message, 'WPS-PowerAddons', 'OK', 'Error') | Out-Null }
    }.GetNewClosure())
    $validate = New-Object Windows.Forms.Button; $validate.Text = 'Configuratie controleren'; $validate.AutoSize = $true
    $test = New-Object Windows.Forms.Button; $test.Text = 'Tool testen'; $test.AutoSize = $true
    $validateAction = {
        try {
            if (-not (Test-WPSToolId $fields.Id.Text)) { throw 'De tool-ID is ongeldig.' }
            if ([IO.Path]::GetExtension($fields.Script.Text) -ine '.ps1' -or -not (Test-Path -LiteralPath $fields.Script.Text -PathType Leaf)) { throw 'Selecteer een bestaand .ps1-bestand.' }
            $tokens = $null; $parseErrors = $null
            [Management.Automation.Language.Parser]::ParseFile($fields.Script.Text, [ref]$tokens, [ref]$parseErrors) | Out-Null
            if ($parseErrors.Count -gt 0) { throw ($parseErrors | ForEach-Object { $_.Message }) -join '; ' }
            [Windows.Forms.MessageBox]::Show('Configuratie en PowerShell-syntaxis zijn geldig. Het script is niet uitgevoerd.', 'WPS-PowerAddons - Controle', 'OK', 'Information') | Out-Null
        } catch { [Windows.Forms.MessageBox]::Show($_.Exception.Message, 'WPS-PowerAddons - Validatie', 'OK', 'Error') | Out-Null }
    }.GetNewClosure()
    $validate.Add_Click($validateAction)
    $test.Add_Click($validateAction)
    $save.Add_Click({
        try {
            if ([IO.Path]::GetExtension($fields.Script.Text) -ine '.ps1' -or -not (Test-Path -LiteralPath $fields.Script.Text -PathType Leaf)) { throw 'Selecteer een bestaand .ps1-bestand.' }
            if (-not (Test-WPSToolId $fields.Id.Text)) { throw 'De tool-ID mag alleen kleine letters, cijfers en koppeltekens bevatten.' }
            $warning = 'Aangepaste PowerShell-scripts kunnen wijzigingen aan uw computer uitvoeren. Controleer het script voordat u het toevoegt. Het script wordt nu niet uitgevoerd. Wilt u doorgaan?'
            if ([Windows.Forms.MessageBox]::Show($warning, 'WPS-PowerAddons - Beveiligingswaarschuwing', 'YesNo', 'Warning', 'Button2') -ne [Windows.Forms.DialogResult]::Yes) { return }
            $definition = [pscustomobject]@{
                Id = $fields.Id.Text; Name = $fields.Name.Text; Category = $fields.Category.Text
                Description = $fields.Description.Text; Version = $fields.Version.Text; Author = $fields.Author.Text
                Tags = @($fields.Tags.Text -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
                Icon = $fields.Icon.Text.Trim()
                TimeoutSeconds = [int]$fields.TimeoutSeconds.Value; RestartBehaviour = [string]$fields.RestartBehaviour.SelectedItem
                RequiresAdmin = $checks.RequiresAdmin.Checked; RequiresConfirmation = $checks.RequiresConfirmation.Checked
                SupportsReadOnlyMode = $checks.SupportsReadOnlyMode.Checked; Enabled = $checks.Enabled.Checked
                Favourite = $checks.Favourite.Checked
            }
            if ($ExistingTool) {
                $created = Set-WPSCustomTool -ExistingTool $ExistingTool -Definition $definition -SourceScript $fields.Script.Text -RootPath $script:WPSUi.RootPath
                $actionText = 'bewerkt'
            } else {
                $created = New-WPSCustomTool -Definition $definition -SourceScript $fields.Script.Text -RootPath $script:WPSUi.RootPath
                $actionText = 'toegevoegd'
            }
            if ($created.Favourite -and $script:WPSUi.Settings.FavouriteToolIds -notcontains $created.Id) {
                $script:WPSUi.Settings.FavouriteToolIds = @($script:WPSUi.Settings.FavouriteToolIds) + @($created.Id)
            } elseif (-not $created.Favourite) {
                $script:WPSUi.Settings.FavouriteToolIds = @($script:WPSUi.Settings.FavouriteToolIds | Where-Object { $_ -ne $created.Id })
            }
            Save-WPSUserPreferences -Settings $script:WPSUi.Settings
            Write-WPSApplicationLog -RootPath $script:WPSUi.RootPath -LogDirectory $script:WPSUi.LogDirectory -Message ('Aangepaste tool {0}: {1} (SHA-256 {2})' -f $actionText, $created.Id, $created.Sha256)
            Import-WPSApplicationState
            $dialog.DialogResult = [Windows.Forms.DialogResult]::OK
            $dialog.Close()
        } catch { [Windows.Forms.MessageBox]::Show($_.Exception.Message, 'WPS-PowerAddons - Fout', 'OK', 'Error') | Out-Null }
    }.GetNewClosure())
    $buttons.Controls.AddRange(@($newScript, $example, $validate, $test, $save, $cancel))
    $row = $layout.RowCount; $layout.RowCount++
    $layout.Controls.Add((New-Object Windows.Forms.Label), 0, $row); $layout.Controls.Add($buttons, 1, $row)
    $dialog.Controls.Add($layout)
    $dialog.ShowDialog($script:WPSUi.Form) | Out-Null
    $dialog.Dispose()
}

function Show-WPSManagementPage {
    $script:WPSUi.PageTitle.Text = 'Mijn tools'
    $panel = $script:WPSUi.Content; $panel.Controls.Clear()
    $toolbar = New-Object Windows.Forms.FlowLayoutPanel; $toolbar.Dock = 'Top'; $toolbar.Height = 42
    foreach ($pair in @(@('Tool toevoegen', 'Add'), @('Configuratie vernieuwen', 'Refresh'), @('ZIP importeren', 'Import'))) {
        $button = New-Object Windows.Forms.Button; $button.Text = $pair[0]; $button.AutoSize = $true
        $action = $pair[1]
        $button.Add_Click({
            if ($action -eq 'Add') { Show-WPSAddToolDialog; Show-WPSManagementPage }
            elseif ($action -eq 'Refresh') { Import-WPSApplicationState; Show-WPSManagementPage }
            else {
                $picker = New-Object Windows.Forms.OpenFileDialog
                $picker.Filter = 'WPS-PowerAddons ZIP (*.zip)|*.zip'
                if ($picker.ShowDialog($script:WPSUi.Form) -eq [Windows.Forms.DialogResult]::OK) {
                    try {
                        if ([Windows.Forms.MessageBox]::Show('ZIP-pakketten bevatten uitvoerbare PowerShell-code. Heeft u het script gecontroleerd?', 'WPS-PowerAddons - Beveiligingswaarschuwing', 'YesNo', 'Warning', 'Button2') -eq [Windows.Forms.DialogResult]::Yes) {
                            Import-WPSCustomToolPackage -PackagePath $picker.FileName -RootPath $script:WPSUi.RootPath | Out-Null
                            Import-WPSApplicationState; Show-WPSManagementPage
                        }
                    } catch { [Windows.Forms.MessageBox]::Show($_.Exception.Message, 'WPS-PowerAddons', 'OK', 'Error') | Out-Null }
                }
                $picker.Dispose()
            }
        }.GetNewClosure())
        $toolbar.Controls.Add($button)
    }
    $panel.Controls.Add($toolbar)
    $grid = New-Object Windows.Forms.DataGridView
    $grid.Dock = 'Fill'; $grid.ReadOnly = $true; $grid.AllowUserToAddRows = $false; $grid.SelectionMode = 'FullRowSelect'; $grid.AutoSizeColumnsMode = 'Fill'
    foreach ($column in @(@('Id', 'Tool-ID'), @('Name', 'Tool'), @('Category', 'Categorie'), @('Enabled', 'Ingeschakeld'), @('Version', 'Versie'))) { [void]$grid.Columns.Add($column[0], $column[1]) }
    foreach ($tool in @($script:WPSUi.Tools | Where-Object Source -eq 'Custom')) { [void]$grid.Rows.Add($tool.Id, $tool.Name, $tool.Category, $tool.Enabled, $tool.Version) }
    $actions = New-Object Windows.Forms.FlowLayoutPanel; $actions.Dock = 'Bottom'; $actions.Height = 42
    $delete = New-Object Windows.Forms.Button; $delete.Text = 'Verwijderen'; $delete.AutoSize = $true
    $delete.Add_Click({
        if ($grid.SelectedRows.Count -eq 0) { return }
        $id = [string]$grid.SelectedRows[0].Cells['Id'].Value
        $tool = $script:WPSUi.Tools | Where-Object { $_.Id -eq $id -and $_.Source -eq 'Custom' } | Select-Object -First 1
        if (-not $tool) { return }
        if ([Windows.Forms.MessageBox]::Show(('Aangepaste tool {0} uit de registratie verwijderen? Het script blijft behouden tenzij u dit apart kiest.' -f $tool.Name), 'WPS-PowerAddons - Verwijderen', 'YesNo', 'Warning', 'Button2') -ne [Windows.Forms.DialogResult]::Yes) { return }
        $deleteScript = [Windows.Forms.MessageBox]::Show('Wilt u ook de scriptmap verwijderen? Logs blijven behouden.', 'WPS-PowerAddons - Script verwijderen', 'YesNo', 'Warning', 'Button2') -eq [Windows.Forms.DialogResult]::Yes
        try { Remove-WPSCustomTool -Tool $tool -RootPath $script:WPSUi.RootPath -DeleteScript:$deleteScript; Import-WPSApplicationState; Show-WPSManagementPage }
        catch { [Windows.Forms.MessageBox]::Show($_.Exception.Message, 'WPS-PowerAddons', 'OK', 'Error') | Out-Null }
    }.GetNewClosure())
    $export = New-Object Windows.Forms.Button; $export.Text = 'Exporteren'; $export.AutoSize = $true
    $export.Add_Click({
        if ($grid.SelectedRows.Count -eq 0) { return }
        $id = [string]$grid.SelectedRows[0].Cells['Id'].Value
        $tool = $script:WPSUi.Tools | Where-Object { $_.Id -eq $id -and $_.Source -eq 'Custom' } | Select-Object -First 1
        $saveDialog = New-Object Windows.Forms.SaveFileDialog; $saveDialog.Filter = 'ZIP-bestand (*.zip)|*.zip'; $saveDialog.FileName = ('{0}.zip' -f $tool.Id)
        if ($tool -and $saveDialog.ShowDialog($script:WPSUi.Form) -eq [Windows.Forms.DialogResult]::OK) {
            try { Export-WPSCustomTool -Tool $tool -RootPath $script:WPSUi.RootPath -Destination $saveDialog.FileName }
            catch { [Windows.Forms.MessageBox]::Show($_.Exception.Message, 'WPS-PowerAddons', 'OK', 'Error') | Out-Null }
        }
        $saveDialog.Dispose()
    }.GetNewClosure())
    $edit = New-Object Windows.Forms.Button; $edit.Text = 'Bewerken'; $edit.AutoSize = $true
    $edit.Add_Click({
        if ($grid.SelectedRows.Count -eq 0) { return }
        $id = [string]$grid.SelectedRows[0].Cells['Id'].Value
        $tool = $script:WPSUi.Tools | Where-Object { $_.Id -eq $id -and $_.Source -eq 'Custom' } | Select-Object -First 1
        if ($tool) { Show-WPSAddToolDialog -ExistingTool $tool; Import-WPSApplicationState; Show-WPSManagementPage }
    }.GetNewClosure())
    $toggle = New-Object Windows.Forms.Button; $toggle.Text = 'In-/uitschakelen'; $toggle.AutoSize = $true
    $toggle.Add_Click({
        if ($grid.SelectedRows.Count -eq 0) { return }
        $id = [string]$grid.SelectedRows[0].Cells['Id'].Value
        $tool = $script:WPSUi.Tools | Where-Object { $_.Id -eq $id -and $_.Source -eq 'Custom' } | Select-Object -First 1
        if ($tool) {
            try {
                $definition = $tool | Select-Object *
                $definition.Enabled = -not [bool]$tool.Enabled
                Set-WPSCustomTool -ExistingTool $tool -Definition $definition -RootPath $script:WPSUi.RootPath | Out-Null
                Import-WPSApplicationState; Show-WPSManagementPage
            } catch { [Windows.Forms.MessageBox]::Show($_.Exception.Message, 'WPS-PowerAddons', 'OK', 'Error') | Out-Null }
        }
    }.GetNewClosure())
    $duplicate = New-Object Windows.Forms.Button; $duplicate.Text = 'Dupliceren'; $duplicate.AutoSize = $true
    $duplicate.Add_Click({
        if ($grid.SelectedRows.Count -eq 0) { return }
        $id = [string]$grid.SelectedRows[0].Cells['Id'].Value
        $tool = $script:WPSUi.Tools | Where-Object { $_.Id -eq $id -and $_.Source -eq 'Custom' } | Select-Object -First 1
        if (-not $tool) { return }
        Add-Type -AssemblyName Microsoft.VisualBasic
        $newId = [Microsoft.VisualBasic.Interaction]::InputBox('Nieuwe unieke tool-ID (kleine letters, cijfers en koppeltekens):', 'WPS-PowerAddons - Tool dupliceren', ('{0}-kopie' -f $tool.Id))
        if (-not $newId) { return }
        try {
            $definition = $tool | Select-Object *
            $definition.Id = $newId
            $definition.Name = '{0} (kopie)' -f $tool.Name
            $source = Resolve-WPSRelativePath -RelativePath $tool.Script -RootPath $script:WPSUi.RootPath -RequireExisting
            New-WPSCustomTool -Definition $definition -SourceScript $source -RootPath $script:WPSUi.RootPath | Out-Null
            Import-WPSApplicationState; Show-WPSManagementPage
        } catch { [Windows.Forms.MessageBox]::Show($_.Exception.Message, 'WPS-PowerAddons', 'OK', 'Error') | Out-Null }
    }.GetNewClosure())
    $actions.Controls.AddRange(@($edit, $toggle, $duplicate, $delete, $export))
    $panel.Controls.Add($grid); $panel.Controls.Add($actions)
}

function Start-WPSApplication {
    param([Parameter(Mandatory = $true)][string]$RootPath)
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    $script:WPSUi = [pscustomobject]@{
        RootPath = $RootPath; Settings = $null; Tools = @(); LogDirectory = ''; ValidationErrors = @()
        Running = @{}; LastResult = $null; Form = $null; Content = $null; PageTitle = $null
        StatusLabel = $null; Progress = $null; ProgressTimer = $null; CancelButton = $null; SearchBox = $null
        OnlyNonAdmin = $null; FavouritesOnly = $null; SortBy = $null; ToolFilter = $null; CategoryFilter = $null; ViewMode = $null; CurrentPage = 'Dashboard'
    }
    Import-WPSApplicationState
    $form = New-Object Windows.Forms.Form
    $form.Text = 'WPS-PowerAddons'
    $form.Size = New-Object Drawing.Size(1280, 820)
    $form.MinimumSize = New-Object Drawing.Size(980, 650)
    $form.StartPosition = 'CenterScreen'
    $form.BackColor = [Drawing.Color]::FromArgb(244, 246, 249)
    $form.Font = New-Object Drawing.Font('Segoe UI', 9)
    $script:WPSUi.Form = $form
    $form.Tag = $script:WPSUi
    $ui = $script:WPSUi
    $main = New-Object Windows.Forms.Panel
    $main.Name = 'WPSMainContent'
    $main.Dock = 'Fill'
    $form.Controls.Add($main)
    $sidebar = New-Object Windows.Forms.Panel
    $sidebar.Name = 'WPSSidebar'
    $sidebar.Dock = 'Left'; $sidebar.Width = 220; $sidebar.BackColor = [Drawing.Color]::FromArgb(23, 32, 51)
    $form.Controls.Add($sidebar)
    $brand = New-Object Windows.Forms.Label
    $brand.Text = 'WPS-PowerAddons'; $brand.ForeColor = [Drawing.Color]::White; $brand.Font = New-Object Drawing.Font('Segoe UI', 15, [Drawing.FontStyle]::Bold)
    $brand.Location = New-Object Drawing.Point(14, 20); $brand.Size = New-Object Drawing.Size(195, 45)
    $sidebar.Controls.Add($brand)
    $navPanel = New-Object Windows.Forms.FlowLayoutPanel
    $navPanel.Dock = 'Fill'; $navPanel.FlowDirection = 'TopDown'; $navPanel.WrapContents = $false; $navPanel.AutoScroll = $true; $navPanel.Padding = New-Object Windows.Forms.Padding(8, 78, 8, 8)
    $sidebar.Controls.Add($navPanel)
    $pages = @(
        @('Dashboard', 'Dashboard'), @('Alle tools', 'Alle tools'), @('SAP', 'SAP'), @('Microsoft 365', 'Microsoft 365'),
        @('Netwerk', 'Netwerk'), @('Windows', 'Windows'), @('Printers', 'Printers'), @('Hardware', 'Hardware'),
        @('Support', 'Support'), @('Mijn tools', 'Mijn tools'), @('Tool toevoegen', 'Tool toevoegen'),
        @('Beheer', 'Beheer'), @('Instellingen', 'Instellingen'), @('Logboeken', 'Logboeken'), @('Over WPS-PowerAddons', 'Over')
    )
    foreach ($page in $pages) {
        $button = New-Object Windows.Forms.Button
        $button.Text = $page[0]; $button.Width = 195; $button.Height = 38; $button.FlatStyle = 'Flat'
        $button.FlatAppearance.BorderSize = 0; $button.TextAlign = 'MiddleLeft'
        $button.BackColor = [Drawing.Color]::FromArgb(23, 32, 51); $button.ForeColor = [Drawing.Color]::White
        $name = $page[1]
        $button.Name = 'WPSNavigation_{0}' -f $name.Replace(' ', '_')
        $button.Add_Click({
            $ui.CurrentPage = $name
            switch ($name) {
                'Dashboard' { Show-WPSDashboard }
                'Alle tools' { Show-WPSToolList }
                'Tool toevoegen' { Show-WPSAddToolDialog; Import-WPSApplicationState; Show-WPSManagementPage }
                'Mijn tools' { Show-WPSManagementPage }
                'Beheer' { Show-WPSManagementPage }
                'Instellingen' { Show-WPSSettingsPage }
                'Logboeken' { Show-WPSLogPage }
                'Over' {
                    [Windows.Forms.MessageBox]::Show("WPS-PowerAddons`r`nVersie 1.0.0`r`nWindows support toolkit voor IT-support.`r`nPowerShell 5.1; Windows 10/11.", 'Over WPS-PowerAddons', 'OK', 'Information') | Out-Null
                }
                default { Show-WPSToolList -Category $name }
            }
        }.GetNewClosure())
        $navPanel.Controls.Add($button)
    }
    $header = New-Object Windows.Forms.Panel; $header.Dock = 'Top'; $header.Height = 98; $header.BackColor = [Drawing.Color]::White
    $main.Controls.Add($header)
    $title = New-Object Windows.Forms.Label
    $title.Text = 'WPS-PowerAddons  |  versie 1.0.0'; $title.Location = New-Object Drawing.Point(20, 10); $title.Size = New-Object Drawing.Size(550, 25)
    $header.Controls.Add($title)
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent().Name
    $mode = if (Test-WPSAdministrator) { 'Gestart als administrator' } else { 'Gestart als standaardgebruiker' }
    $context = New-Object Windows.Forms.Label
    $context.Text = ('Computer: {0}   |   Gebruiker: {1}   |   {2}' -f $env:COMPUTERNAME, $identity, $mode)
    $context.Location = New-Object Drawing.Point(20, 38); $context.Size = New-Object Drawing.Size(720, 22)
    $header.Controls.Add($context)
    $script:WPSUi.SearchBox = New-Object Windows.Forms.TextBox
    $script:WPSUi.SearchBox.Location = New-Object Drawing.Point(20, 65); $script:WPSUi.SearchBox.Size = New-Object Drawing.Size(400, 24)
    $header.Controls.Add($script:WPSUi.SearchBox)
    $refresh = New-Object Windows.Forms.Button; $refresh.Text = 'Configuratie vernieuwen'; $refresh.Location = New-Object Drawing.Point(432, 63); $refresh.Size = New-Object Drawing.Size(175, 28)
    $refresh.Add_Click({
        $query = $script:WPSUi.SearchBox.Text
        Import-WPSApplicationState
        $script:WPSUi.SearchBox.Text = $query
        switch ($script:WPSUi.CurrentPage) {
            'Dashboard' { Show-WPSDashboard }
            'Instellingen' { Show-WPSSettingsPage }
            'Logboeken' { Show-WPSLogPage }
            'Mijn tools' { Show-WPSManagementPage }
            default { Show-WPSToolList -Category $script:WPSUi.CurrentPage }
        }
        if ($script:WPSUi.ValidationErrors.Count -gt 0) {
            [Windows.Forms.MessageBox]::Show(($script:WPSUi.ValidationErrors -join "`r`n"), 'WPS-PowerAddons - Validatiefouten', 'OK', 'Warning') | Out-Null
        } else { [Windows.Forms.MessageBox]::Show('Configuratie vernieuwd.', 'WPS-PowerAddons', 'OK', 'Information') | Out-Null }
    })
    $header.Controls.Add($refresh)
    $body = New-Object Windows.Forms.Panel; $body.Dock = 'Fill'; $main.Controls.Add($body)
    $script:WPSUi.PageTitle = New-Object Windows.Forms.Label
    $script:WPSUi.PageTitle.Text = 'Dashboard'; $script:WPSUi.PageTitle.Dock = 'Top'; $script:WPSUi.PageTitle.Height = 38
    $script:WPSUi.PageTitle.Font = New-Object Drawing.Font('Segoe UI', 16, [Drawing.FontStyle]::Bold)
    $body.Controls.Add($script:WPSUi.PageTitle)
    $script:WPSUi.Content = New-Object Windows.Forms.Panel
    $script:WPSUi.Content.Dock = 'Fill'; $script:WPSUi.Content.BackColor = [Drawing.Color]::FromArgb(244, 246, 249)
    $body.Controls.Add($script:WPSUi.Content)
    $footer = New-Object Windows.Forms.StatusStrip
    $script:WPSUi.StatusLabel = New-Object Windows.Forms.ToolStripStatusLabel
    $script:WPSUi.StatusLabel.Text = 'Gereed.'
    $script:WPSUi.Progress = New-Object Windows.Forms.ToolStripProgressBar
    $script:WPSUi.Progress.Style = 'Marquee'; $script:WPSUi.Progress.Visible = $false
    $script:WPSUi.CancelButton = New-Object Windows.Forms.ToolStripStatusLabel
    $script:WPSUi.CancelButton.Text = 'Annuleren niet beschikbaar tijdens veilige uitvoering'
    $footer.Items.Add($script:WPSUi.StatusLabel) | Out-Null; $footer.Items.Add($script:WPSUi.Progress) | Out-Null; $footer.Items.Add($script:WPSUi.CancelButton) | Out-Null
    $main.Controls.Add($footer)
    $script:WPSUi.ProgressTimer = New-Object Windows.Forms.Timer
    $script:WPSUi.ProgressTimer.Interval = 300
    $script:WPSUi.ProgressTimer.Add_Tick({
        foreach ($key in @($script:WPSUi.Running.Keys)) {
            $entry = $script:WPSUi.Running[$key]
            if ($entry.Async.IsCompleted) { Complete-WPSAsyncTool -ToolId $key }
        }
    })
    $form.Add_FormClosing({
        if ($script:WPSUi.Running.Count -gt 0) {
            $answer = [Windows.Forms.MessageBox]::Show('Er wordt nog een tool uitgevoerd. De toepassing sluiten stopt deze tool niet gegarandeerd. Toch afsluiten?', 'WPS-PowerAddons', 'YesNo', 'Warning', 'Button2')
            if ($answer -ne [Windows.Forms.DialogResult]::Yes) { $_.Cancel = $true }
        }
    })
    if (Test-Path -LiteralPath (Join-Path $RootPath 'assets\app.ico') -PathType Leaf) {
        try { $form.Icon = New-Object Drawing.Icon((Join-Path $RootPath 'assets\app.ico')) } catch { Write-WPSApplicationLog -RootPath $RootPath -LogDirectory $script:WPSUi.LogDirectory -Level WARN -Message 'Optioneel pictogram kon niet worden geladen.' }
    }
    Show-WPSDashboard
    if ($script:WPSUi.ValidationErrors.Count -gt 0) {
        [Windows.Forms.MessageBox]::Show(("Er zijn configuratiefouten gevonden. Geldige tools zijn geladen.`r`n`r`n{0}" -f ($script:WPSUi.ValidationErrors -join "`r`n")), 'WPS-PowerAddons - Validatie', 'OK', 'Warning') | Out-Null
    }
    [void]$form.ShowDialog()
    $script:WPSUi.ProgressTimer.Dispose()
    $form.Dispose()
}
