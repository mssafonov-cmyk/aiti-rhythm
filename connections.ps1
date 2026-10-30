param([switch]$ValidateOnly,[switch]$SelfTest,[string]$DataRoot)
$ErrorActionPreference='Stop'

$script:dataRoot=if($DataRoot){$DataRoot}else{Join-Path $env:LOCALAPPDATA 'AITI/Rhythm/data'}
[void][IO.Directory]::CreateDirectory($dataRoot)
Add-Type -AssemblyName PresentationFramework
[xml]$xaml=@'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" Title="АйТи:Ритм — подключения" Width="530" Height="760" MinWidth="420" MinHeight="500" WindowStartupLocation="CenterScreen" FontFamily="Segoe UI" Background="#F4F5F7">
 <DockPanel Margin="20">
  <StackPanel DockPanel.Dock="Bottom" Margin="0,12,0,0">
   <TextBlock x:Name="Status" TextWrapping="Wrap" Foreground="#A02B2B"/>
   <StackPanel Orientation="Horizontal" HorizontalAlignment="Right"><Button x:Name="Cancel" Content="Отмена" Padding="16,7" Margin="0,0,8,0"/><Button x:Name="Save" Content="Сохранить" Padding="16,7"/></StackPanel>
  </StackPanel>
  <ScrollViewer VerticalScrollBarVisibility="Auto"><StackPanel>
   <TextBlock Text="Ваши инструменты" FontSize="21" FontWeight="SemiBold"/>
   <TextBlock x:Name="Detection" TextWrapping="Wrap" Margin="0,8,0,0" Foreground="#38596A"/>
   <TextBlock Text="Сначала войдите в Codex и Claude Code обычным способом. Панель читает только журналы выбранных профилей." TextWrapping="Wrap" Margin="0,8,0,12"/>
   <CheckBox x:Name="Codex" Content="Показывать Codex"/>
   <TextBlock Text="Папка Codex (пусто — профиль текущего пользователя)" Margin="0,6,0,3"/><TextBox x:Name="CodexHome" Padding="5"/>
   <TextBlock Text="Путь к codex.exe (пусто — найти автоматически)" Margin="0,6,0,3"/><TextBox x:Name="CodexExe" Padding="5"/>
   <CheckBox x:Name="Limits" Content="Читать доступную квоту через Codex" Margin="0,7,0,12"/>
   <CheckBox x:Name="Claude" Content="Показывать Claude Code"/>
   <TextBlock Text="Источник Claude" Margin="0,6,0,3"/><ComboBox x:Name="ClaudeSource"><ComboBoxItem Content="Мой локальный Claude Code" Tag="local"/><ComboBoxItem Content="Внешний сборщик JSON" Tag="external"/></ComboBox>
   <TextBlock Text="Команда внешнего Claude (JSON-массив, дополнительно)" Margin="0,6,0,3"/><PasswordBox x:Name="ClaudeCommand" Padding="5"/>
   <TextBlock Text="Папка Claude (пусто — профиль текущего пользователя)" Margin="0,6,0,3"/><TextBox x:Name="ClaudeHome" Padding="5"/>
   <TextBlock Text="Для WSL укажите папку .claude через путь \wsl.localhost. Точная квота Claude может быть недоступна." TextWrapping="Wrap" FontSize="11" Foreground="#59616B" Margin="0,4,0,14"/>
   <CheckBox x:Name="Calendar" Content="Показывать встречи из моего календаря" FontWeight="SemiBold"/>
   <TextBlock Text="Способ подключения" Margin="0,6,0,3"/><ComboBox x:Name="Kind"><ComboBoxItem Content="Google / Яндекс / другой iCal" Tag="ical"/><ComboBoxItem Content="Яндекс / другой CalDAV" Tag="caldav"/><ComboBoxItem Content="1С / другая публикация OData" Tag="odata"/><ComboBoxItem Content="Внешний сборщик JSON" Tag="external"/></ComboBox>
   <TextBlock Text="Команда внешнего календаря (JSON-массив, дополнительно)" Margin="0,6,0,3"/><PasswordBox x:Name="CalendarCommand" Padding="5"/>
   <TextBlock Text="Название источника (например, Рабочий календарь)" Margin="0,6,0,3"/><TextBox x:Name="CalendarName" Padding="5"/>
   <TextBlock Text="Часовой пояс календаря (IANA)" Margin="0,6,0,3"/><TextBox x:Name="Timezone" Padding="5"/>
   <TextBlock Text="Личная HTTPS-ссылка iCal / адрес коллекции CalDAV или OData" TextWrapping="Wrap" Margin="0,6,0,3"/><PasswordBox x:Name="CalendarUrl" Padding="5"/>
   <TextBlock Text="Логин (только если он требуется источнику)" Margin="0,6,0,3"/><TextBox x:Name="Username" Padding="5"/>
   <TextBlock Text="Пароль приложения / пароль личной публикации" Margin="0,6,0,3"/><PasswordBox x:Name="Password" Padding="5"/>
   <TextBlock Text="Ссылки и пароли шифруются Windows для вашего пользователя. Пустые поля сохраняют прежнее подключение. Отключение календаря удаляет его сохраненные доступы." TextWrapping="Wrap" FontSize="11" Foreground="#59616B" Margin="0,6,0,8"/>
   <TextBlock Text="Только для OData: соответствие полей (JSON)" Margin="0,6,0,3"/><TextBox x:Name="Mapping" Padding="5" TextWrapping="Wrap" AcceptsReturn="True" MinHeight="46"/>
   <TextBlock Text="Для OData нужен ограниченный запрос к JSON-коллекции и собственные права чтения. Имена реквизитов зависят от вашей конфигурации 1С." TextWrapping="Wrap" FontSize="11" Foreground="#59616B" Margin="0,4,0,14"/>
   <CheckBox x:Name="Cube" Content="Выводить на мой кубик" FontWeight="SemiBold"/>
   <TextBlock Text="Локальный IPv4-адрес совместимого устройства" Margin="0,6,0,3"/><TextBox x:Name="CubeHost" Padding="5"/>
   <TextBlock Text="Поворот экрана" Margin="0,6,0,3"/><ComboBox x:Name="Rotation"><ComboBoxItem Content="0"/><ComboBoxItem Content="90"/><ComboBoxItem Content="180"/><ComboBoxItem Content="270"/></ComboBox>
   <CheckBox x:Name="Titles" Content="Разрешить названия встреч на кубике" Margin="0,8,0,4"/>
   <TextBlock Text="Совместимость: HelloCubic-Lite / SmallTV-Ultra, штатная прошивка. На устройство передаются изображения метрик; доступы к сервисам не передаются. Вывод меняет текущую картинку и отключает автослайдшоу устройства." TextWrapping="Wrap" FontSize="11" Foreground="#59616B" Margin="0,4,0,12"/>
  </StackPanel></ScrollViewer>
 </DockPanel>
</Window>
'@
$window=[Windows.Markup.XamlReader]::Load([Xml.XmlNodeReader]::new($xaml))
$controls=@{};foreach($name in @('ClaudeSource','ClaudeCommand','CalendarCommand','Codex','CodexHome','CodexExe','Limits','Claude','ClaudeHome','Calendar','Kind','CalendarName','Timezone','CalendarUrl','Username','Password','Mapping','Cube','CubeHost','Rotation','Titles','Save','Cancel','Status')){$controls[$name]=$window.FindName($name)}
$configPath=Join-Path $dataRoot 'connections.json'
$discoveryPath=Join-Path $dataRoot 'discovery.json'
if(Test-Path -LiteralPath $discoveryPath){$found=Get-Content -LiteralPath $discoveryPath -Raw -Encoding UTF8|ConvertFrom-Json;$codexFound=if($found.codex_journals){'Codex: найдены журналы'}elseif($found.codex_installed){'Codex: установлен, запустите первую сессию'}else{'Codex: не найден'};$claudeFound=if($found.claude_external){'Claude: внешний источник'}elseif($found.claude_journals){'Claude Code: найдены журналы'}elseif($found.claude_installed){'Claude Code: установлен, запустите первую сессию'}else{'Claude Code: не найден'};$window.FindName('Detection').Text=$codexFound+"`n"+$claudeFound}
if(Test-Path -LiteralPath $configPath){$config=Get-Content -LiteralPath $configPath -Raw -Encoding UTF8|ConvertFrom-Json}else{$config=$null}
$controls.Codex.IsChecked=if($config){[bool]$config.codex.enabled}else{$true};$controls.Limits.IsChecked=if($config){[bool]$config.codex.limits}else{$true}
$controls.Claude.IsChecked=if($config){[bool]$config.claude.enabled}else{$true};$controls.Calendar.IsChecked=[bool]$config.calendar.enabled;$controls.Cube.IsChecked=[bool]$config.cube.enabled
$controls.CodexHome.Text=[string]$config.codex.home;$controls.CodexExe.Text=[string]$config.codex.executable;$controls.ClaudeHome.Text=[string]$config.claude.home
$controls.CalendarName.Text=[string]$config.calendar.name;$controls.Timezone.Text=if($config.calendar.timezone){$config.calendar.timezone}else{'Europe/Moscow'}
$controls.ClaudeSource.SelectedIndex=0;foreach($item in $controls.ClaudeSource.Items){if($item.Tag -eq $config.claude.source){$controls.ClaudeSource.SelectedItem=$item}}
$controls.Kind.SelectedIndex=0;foreach($item in $controls.Kind.Items){if($item.Tag -eq $config.calendar.kind){$controls.Kind.SelectedItem=$item}}
$controls.Mapping.Text=if($config.calendar.mapping){$config.calendar.mapping|ConvertTo-Json -Compress}else{'{"id":"id","subject":"subject","start":"start","end":"end","url":"url"}'}
$controls.CubeHost.Text=[string]$config.cube.host;$controls.Titles.IsChecked=[bool]$config.cube.show_titles;$controls.Rotation.SelectedIndex=0
foreach($item in $controls.Rotation.Items){if([string]$item.Content -eq [string]$config.cube.rotation){$controls.Rotation.SelectedItem=$item}}
$controls.Cancel.Add_Click({$window.Close()})
$controls.Save.Add_Click({
 try{
  $values=@{
   codex=@{enabled=[bool]$controls.Codex.IsChecked;home=$controls.CodexHome.Text.Trim();executable=$controls.CodexExe.Text.Trim();limits=[bool]$controls.Limits.IsChecked}
   claude=@{enabled=[bool]$controls.Claude.IsChecked;home=$controls.ClaudeHome.Text.Trim();source=[string]$controls.ClaudeSource.SelectedItem.Tag}
   calendar=@{enabled=[bool]$controls.Calendar.IsChecked;kind=[string]$controls.Kind.SelectedItem.Tag;name=$controls.CalendarName.Text.Trim();timezone=$controls.Timezone.Text.Trim();mapping=($controls.Mapping.Text|ConvertFrom-Json)}
   cube=@{enabled=[bool]$controls.Cube.IsChecked;host=$controls.CubeHost.Text.Trim();rotation=[int][string]$controls.Rotation.SelectedItem.Content;show_titles=[bool]$controls.Titles.IsChecked}
   secrets=@{claude_command=$(if($controls.ClaudeCommand.Password){ConvertFrom-Json -InputObject $controls.ClaudeCommand.Password}else{$null});calendar_command=$(if($controls.CalendarCommand.Password){ConvertFrom-Json -InputObject $controls.CalendarCommand.Password}else{$null});calendar_url=$controls.CalendarUrl.Password.Trim();calendar_username=$controls.Username.Text.Trim();calendar_password=$controls.Password.Password}
  }
  $python=$env:RHYTHM_CORE_EXE
  $start=[Diagnostics.ProcessStartInfo]::new();$start.FileName=$python;$start.Arguments=$env:RHYTHM_CORE_PREFIX+' --configure-stdin';$start.UseShellExecute=$false;$start.CreateNoWindow=$true;$start.RedirectStandardInput=$true;$start.RedirectStandardOutput=$true;$start.RedirectStandardError=$true
  $process=[Diagnostics.Process]::Start($start);$payload=[Text.Encoding]::UTF8.GetBytes(($values|ConvertTo-Json -Depth 8 -Compress));$process.StandardInput.BaseStream.Write($payload,0,$payload.Length);$process.StandardInput.BaseStream.Close();$output=$process.StandardOutput.ReadToEnd();$errorText=$process.StandardError.ReadToEnd();$process.WaitForExit()
  if($process.ExitCode -ne 0){$controls.Status.Text='Проверьте поля подключения. Нужен HTTPS-адрес календаря; для кубика — локальный IPv4.';return}
  $window.Close()
 }catch{if($SelfTest){throw};$controls.Status.Text='Не удалось сохранить. Проверьте формат настроек и установленный Python.'}
})
if($ValidateOnly){Write-Output 'Connections dialog parsed; no secrets read or settings changed.'}
elseif($SelfTest){
 $controls.CodexHome.Text=Join-Path $dataRoot 'fixture-codex';$controls.ClaudeHome.Text=Join-Path $dataRoot 'fixture-claude';$controls.Limits.IsChecked=$false;$controls.Calendar.IsChecked=$false;$controls.Cube.IsChecked=$false
 $controls.Save.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Primitives.ButtonBase]::ClickEvent))
 if($controls.Status.Text -or -not (Test-Path -LiteralPath $configPath)){throw 'Settings save bridge failed'}
 Write-Output 'Settings form saved isolated test profiles successfully.'
}else{[void]$window.ShowDialog()}
