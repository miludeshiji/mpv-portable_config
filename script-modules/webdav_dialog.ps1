param(
    [Parameter(Mandatory)]
    [string] $ConfigPath
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
Add-Type -AssemblyName System.Windows.Forms
[Windows.Forms.Application]::EnableVisualStyles()

function Save-WebDavLibrary($Library) {
    $mutex = [Threading.Mutex]::new($false, 'Local\mpv-webdav-libraries')
    $locked = $false
    $temporaryPath = "$ConfigPath.tmp"
    try {
        try {
            $locked = $mutex.WaitOne([TimeSpan]::FromSeconds(3))
        } catch [Threading.AbandonedMutexException] {
            $locked = $true
        }
        if (!$locked) { throw '另一个 mpv 窗口正在保存 WebDAV 库，请重试。' }

        $libraries = @()
        if ([IO.File]::Exists($ConfigPath)) {
            $libraries = ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($ConfigPath)) -NoEnumerate
            if ($libraries -isnot [array]) { throw 'WebDAV 库配置格式有误。' }
        }
        $libraries = @($libraries | Where-Object { $_.url -cne $Library.url })
        $libraries += $Library
        $json = ConvertTo-Json -InputObject $libraries -Depth 4
        [IO.File]::WriteAllText($temporaryPath, $json)
        [IO.File]::Move($temporaryPath, $ConfigPath, $true)
    } finally {
        if ($locked) {
            try { [IO.File]::Delete($temporaryPath) } finally { $mutex.ReleaseMutex() }
        }
        $mutex.Dispose()
    }
}

$form = [Windows.Forms.Form]@{
    Text = '添加 WebDAV 库'
    StartPosition = 'CenterScreen'
    FormBorderStyle = 'FixedDialog'
    AutoScaleMode = 'Dpi'
    ClientSize = [Drawing.Size]::new(520, 222)
    MaximizeBox = $false
    MinimizeBox = $false
    TopMost = $true
}

$table = [Windows.Forms.TableLayoutPanel]@{
    Dock = 'Fill'
    ColumnCount = 2
    Padding = [Windows.Forms.Padding]::new(16)
}
$table.ColumnStyles.Add([Windows.Forms.ColumnStyle]::new('AutoSize')) | Out-Null
$table.ColumnStyles.Add([Windows.Forms.ColumnStyle]::new('Percent', 100)) | Out-Null
$form.Controls.Add($table)

$fields = @{}
$captions = [ordered]@{
    url = '目录地址'
    name = '库名称'
    username = '用户名'
    password = '密码'
}
foreach ($field in $captions.Keys) {
    $row = $table.RowCount++
    $table.RowStyles.Add([Windows.Forms.RowStyle]::new('AutoSize')) | Out-Null
    $label = [Windows.Forms.Label]@{ Text = $captions[$field]; Anchor = 'Left'; AutoSize = $true }
    $box = [Windows.Forms.TextBox]@{ Dock = 'Top'; Margin = [Windows.Forms.Padding]::new(10, 4, 0, 6) }
    $table.Controls.Add($label, 0, $row)
    $table.Controls.Add($box, 1, $row)
    $fields[$field] = $box
}
$fields.url.PlaceholderText = 'https://example.com/dav/'
$fields.name.PlaceholderText = '可选，默认使用服务器名称'
$fields.username.PlaceholderText = '匿名访问可留空'
$fields.password.UseSystemPasswordChar = $true

$buttons = [Windows.Forms.FlowLayoutPanel]@{ Dock = 'Fill'; FlowDirection = 'RightToLeft'; AutoSize = $true }
$save = [Windows.Forms.Button]@{ Text = '保存'; AutoSize = $true }
$cancel = [Windows.Forms.Button]@{ Text = '取消'; AutoSize = $true; DialogResult = 'Cancel' }
$buttons.Controls.AddRange(@($save, $cancel))
$table.Controls.Add($buttons, 1, $table.RowCount)
$form.AcceptButton = $save
$form.CancelButton = $cancel

$save.Add_Click({
    try {
        $uri = $null
        if (![Uri]::TryCreate($fields.url.Text.Trim(), 'Absolute', [ref] $uri) -or
            $uri.Scheme -notin @('http', 'https') -or !$uri.Host -or
            $uri.UserInfo -or $uri.Query -or $uri.Fragment) {
            throw '请输入完整的 HTTP 或 HTTPS WebDAV 目录地址。用户名和密码请填在下方。'
        }

        $builder = [UriBuilder]::new($uri)
        $builder.Host = $uri.IdnHost
        $url = $builder.Uri.AbsoluteUri.TrimEnd('/') + '/'
        $name = $fields.name.Text.Trim()
        if (!$name) { $name = $uri.IdnHost }
        $username = $fields.username.Text
        $password = $fields.password.Text
        if ($username.Contains(':') -or (!$username -and $password)) {
            throw '请输入有效的用户名，用户名中不能包含冒号。'
        }

        $authorization = ''
        if ($username) {
            $bytes = [Text.Encoding]::UTF8.GetBytes("${username}:$password")
            $authorization = 'Basic ' + [Convert]::ToBase64String($bytes)
        }
        Save-WebDavLibrary @{ name = $name; url = $url; authorization = $authorization }
        $form.Tag = $url
        $form.DialogResult = 'OK'
    } catch {
        [Windows.Forms.MessageBox]::Show($form, $_.Exception.Message, 'WebDAV', 'OK', 'Warning') | Out-Null
    }
})

try {
    if ($form.ShowDialog() -eq [Windows.Forms.DialogResult]::OK) {
        [Console]::WriteLine((ConvertTo-Json -InputObject $form.Tag -Compress))
    }
} finally {
    $form.Dispose()
}
