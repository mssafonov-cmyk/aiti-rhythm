# Native toasts retain an immutable session reference, including across app restarts.
function SessionUrl($item){
 $id=[string]$item.id;if($id -notmatch '^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$'){return $null}
 if($item.navigation.target_id){$id=[string]$item.navigation.target_id;if($id -notmatch '^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$'){return $null}}
 if($item.provider -eq 'Claude' -and $item.navigation.kind -eq 'claude_vscode'){return 'vscode://anthropic.claude-code/open?session='+$id}
 if($item.provider -and $item.provider -ne 'Codex'){return $null}
 switch($item.navigation.kind){
  'codex_desktop'{return 'codex://threads/'+$id}
  'codex_vscode'{return 'vscode://openai.chatgpt/local/'+$id}
  'codex_cursor'{return 'cursor://openai.chatgpt/local/'+$id}
  'codex_windsurf'{return 'windsurf://openai.chatgpt/local/'+$id}
 };return $null
}
function SessionChoices($provider){
 if($provider -eq 'Claude'){[pscustomobject]@{title='Claude в VS Code';kind='claude_vscode'}}
 elseif($provider -eq 'Codex' -or -not $provider){
  [pscustomobject]@{title='Codex Desktop';kind='codex_desktop'}
  [pscustomobject]@{title='Codex в VS Code';kind='codex_vscode'}
  [pscustomobject]@{title='Codex в Cursor';kind='codex_cursor'}
 }
}
function OpenSession($item){
 if($item -is [string]){
  $id=$item;$found=@(@($data.codex.sessions)+@($data.claude.sessions)+@($data.antigravity.sessions)+@((UsageData).burn.leaders)|Where-Object {$_.id -eq $id}|Select-Object -First 1)
  $item=if($found.Count){$found[0]}else{[pscustomobject]@{provider='Codex';id=$id}}
 }
 if([string]$item.id -notmatch '^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$'){return}
 $url=SessionUrl $item
 if($SelfTest){$script:testSessionUrl=$url;$script:testSessionChoice=(-not $url);$script:testSessionChoices=@(SessionChoices $item.provider);return}
 if($url){
  try{Start-Process -FilePath $url;$script:notice='Открываю выбранную сессию…'}catch{$script:notice='Приложение не приняло ссылку на сессию'}
 }else{
  $choose=[Windows.Controls.ContextMenu]::new();$choose.Background=Brush '#1C232C';$choose.Foreground=Brush '#E5E8EB';$choose.BorderBrush=Brush '#3A4652'
  $title=[Windows.Controls.MenuItem]::new();$title.Header='Где открыть эту сессию?';$title.IsEnabled=$false;[void]$choose.Items.Add($title)
  $options=@(SessionChoices $item.provider)
  foreach($option in $options){
   $entry=[Windows.Controls.MenuItem]::new();$entry.Header=$option.title;$entry.Tag=@{provider=$item.provider;id=$item.id;navigation=@{kind=$option.kind}}
   $entry.Add_Click({param($s,$e) OpenSession $s.Tag});[void]$choose.Items.Add($entry)
  }
  $copy=[Windows.Controls.MenuItem]::new();$copy.Header='Скопировать ID сессии (терминал / другой клиент)';$copy.Tag=[string]$item.id;$copy.Add_Click({param($s,$e) [Windows.Clipboard]::SetText($s.Tag)});[void]$choose.Items.Add($copy)
  $win.Show();[void]$win.Activate();$choose.PlacementTarget=$Shell;$choose.IsOpen=$true
  $script:notice='Приложение не определено по журналу; выберите его'
 }
 $script:noticeAt=Get-Date;$Foot.Text=$notice
}
function ShowBurnNotice($burn){
 $leader=@($burn.leaders|Select-Object -First 1)
 $item=if($leader.Count){$leader[0]}else{[pscustomobject]@{}}
 $ref=[guid]::NewGuid().ToString();$folder=Join-Path $root 'notifications';[void][IO.Directory]::CreateDirectory($folder)
 $nav=@{kind=[string]$item.navigation.kind};if($item.navigation.target_id){$nav.target_id=[string]$item.navigation.target_id}
 $target=@{id=[string]$item.id;provider=$(if($item.provider){[string]$item.provider}else{'Codex'});navigation=$nav}
 $record=@{at=(NowSeconds);target=$target};$file=Join-Path $folder ($ref+'.json')
 [IO.File]::WriteAllText($file,($record|ConvertTo-Json -Depth 6),[Text.UTF8Encoding]::new($false))
 # Expired references cannot be activated; remove only our UUID files in this directory.
 $prefix=[IO.Path]::GetFullPath($folder).TrimEnd('\')+'\'
 foreach($old in @(Get-ChildItem -LiteralPath $folder -File -Filter '*.json')){
  if($old.BaseName -match '^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$' -and $old.LastWriteTimeUtc -lt [DateTime]::UtcNow.AddDays(-2) -and $old.FullName.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase)){Remove-Item -LiteralPath $old.FullName -ErrorAction SilentlyContinue}
 }
 $uri='aiti-rhythm://notification/'+$ref
 $body=[Security.SecurityElement]::Escape((BurnNoticeText $burn))
 $xmlText='<toast activationType="protocol" launch="'+$uri+'"><visual><binding template="ToastGeneric"><text>Расход токенов ускорился</text><text>'+$body+'</text></binding></visual></toast>'
 if($SelfTest){$script:testToastXml=$xmlText;$script:testToastRef=$ref;return $true}
 try{
  $null=[Windows.UI.Notifications.ToastNotificationManager,Windows.UI.Notifications,ContentType=WindowsRuntime]
  $doc=[Windows.Data.Xml.Dom.XmlDocument,Windows.Data.Xml.Dom.XmlDocument,ContentType=WindowsRuntime]::new();$doc.LoadXml($xmlText)
  $toast=[Windows.UI.Notifications.ToastNotification,Windows.UI.Notifications,ContentType=WindowsRuntime]::new($doc);$toast.Tag=$ref.Replace('-','').Substring(0,16);$toast.Group='burn';$toast.ExpirationTime=[DateTimeOffset]::Now.AddDays(1)
  [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier('AITI.Rhythm').Show($toast)
  $script:lastNoticeChannel='native'
 }catch{
  # Fallback remains explicitly tied to the last visible balloon, not the live leader.
  $script:balloonTarget=$target;$tray.ShowBalloonTip(7000,'Расход токенов ускорился',(BurnNoticeText $burn),[Windows.Forms.ToolTipIcon]::Warning)
  $script:lastNoticeChannel='tray'
 }
 return $true
}
