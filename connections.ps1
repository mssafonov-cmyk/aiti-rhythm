param([switch]$ValidateOnly,[switch]$SelfTest,[string]$DataRoot)
$ErrorActionPreference='Stop'

$script:dataRoot=if($DataRoot){$DataRoot}else{Join-Path $env:LOCALAPPDATA 'AITI/Rhythm/data'}
[void][IO.Directory]::CreateDirectory($dataRoot)
Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase
[xml]$xaml=@'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
 Title="АйТи:Ритм — подключения" Width="620" Height="720" MinWidth="520" MinHeight="520" WindowStartupLocation="CenterScreen"
 WindowStyle="None" AllowsTransparency="True" Background="Transparent" ResizeMode="CanResizeWithGrip" FontFamily="Segoe UI" FontSize="12" Foreground="#EDF4FD">
 <Window.Resources>
  <Style TargetType="TextBlock"><Setter Property="TextWrapping" Value="Wrap"/></Style>
  <Style x:Key="Hint" TargetType="TextBlock"><Setter Property="Foreground" Value="#94A7BF"/><Setter Property="TextWrapping" Value="Wrap"/><Setter Property="LineHeight" Value="18"/></Style>
  <Style x:Key="Caption" TargetType="TextBlock" BasedOn="{StaticResource Hint}"><Setter Property="Margin" Value="0,16,0,6"/></Style>
  <Style x:Key="Card" TargetType="Border"><Setter Property="Background" Value="#1C2530"/><Setter Property="BorderBrush" Value="#344354"/><Setter Property="BorderThickness" Value="1"/><Setter Property="CornerRadius" Value="13"/><Setter Property="Padding" Value="20"/><Setter Property="Margin" Value="0,0,0,12"/></Style>
  <Style TargetType="Button">
   <Setter Property="Foreground" Value="#D9E5F4"/><Setter Property="Background" Value="#263449"/><Setter Property="BorderBrush" Value="#34485F"/><Setter Property="BorderThickness" Value="1"/><Setter Property="Padding" Value="16,9"/><Setter Property="Cursor" Value="Hand"/>
   <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Button"><Border x:Name="B" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="8" Padding="{TemplateBinding Padding}"><ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/></Border><ControlTemplate.Triggers><Trigger Property="IsMouseOver" Value="True"><Setter TargetName="B" Property="BorderBrush" Value="#56D8F1"/></Trigger><Trigger Property="IsKeyboardFocused" Value="True"><Setter TargetName="B" Property="BorderBrush" Value="#56D8F1"/></Trigger><Trigger Property="IsPressed" Value="True"><Setter Property="Opacity" Value="0.75"/></Trigger><Trigger Property="IsEnabled" Value="False"><Setter Property="Opacity" Value="0.5"/></Trigger></ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter>
  </Style>
  <Style x:Key="Field" TargetType="Control"><Setter Property="Background" Value="#141C26"/><Setter Property="Foreground" Value="#EDF4FD"/><Setter Property="BorderBrush" Value="#405267"/><Setter Property="BorderThickness" Value="1"/><Setter Property="Padding" Value="10,8"/><Setter Property="MinHeight" Value="36"/>
   <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Control"><Border x:Name="B" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="7"><ScrollViewer x:Name="PART_ContentHost" Margin="{TemplateBinding Padding}"/></Border><ControlTemplate.Triggers><Trigger Property="IsKeyboardFocusWithin" Value="True"><Setter TargetName="B" Property="BorderBrush" Value="#56D8F1"/></Trigger><Trigger Property="IsEnabled" Value="False"><Setter Property="Opacity" Value="0.5"/></Trigger></ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter>
  </Style>
  <Style TargetType="TextBox" BasedOn="{StaticResource Field}"><Setter Property="CaretBrush" Value="#56D8F1"/><Setter Property="SelectionBrush" Value="#395974"/></Style>
  <Style TargetType="PasswordBox" BasedOn="{StaticResource Field}"><Setter Property="CaretBrush" Value="#56D8F1"/></Style>
  <Style TargetType="CheckBox"><Setter Property="Cursor" Value="Hand"/><Setter Property="Foreground" Value="#EDF4FD"/><Setter Property="VerticalContentAlignment" Value="Center"/>
   <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="CheckBox"><Grid Background="Transparent"><Grid.ColumnDefinitions><ColumnDefinition Width="46"/><ColumnDefinition/></Grid.ColumnDefinitions><Border x:Name="Track" Width="34" Height="20" Background="#344354" CornerRadius="10" HorizontalAlignment="Left" VerticalAlignment="Center"><Ellipse x:Name="Knob" Width="14" Height="14" Fill="#A8B8CB" Margin="3" HorizontalAlignment="Left"/></Border><ContentPresenter Grid.Column="1" VerticalAlignment="Center" RecognizesAccessKey="True"/><Border x:Name="Focus" BorderBrush="Transparent" BorderThickness="1" CornerRadius="5" Grid.ColumnSpan="2" Margin="-3"/></Grid><ControlTemplate.Triggers><Trigger Property="IsChecked" Value="True"><Setter TargetName="Track" Property="Background" Value="#56D8F1"/><Setter TargetName="Knob" Property="Fill" Value="#13202B"/><Setter TargetName="Knob" Property="HorizontalAlignment" Value="Right"/></Trigger><Trigger Property="IsKeyboardFocused" Value="True"><Setter TargetName="Focus" Property="BorderBrush" Value="#56D8F1"/></Trigger><Trigger Property="IsEnabled" Value="False"><Setter Property="Opacity" Value="0.5"/></Trigger></ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter>
  </Style>
  <Style TargetType="RadioButton"><Setter Property="Foreground" Value="#94A7BF"/><Setter Property="Cursor" Value="Hand"/><Setter Property="Margin" Value="3"/>
   <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="RadioButton"><Border x:Name="B" Background="Transparent" CornerRadius="8" BorderThickness="1" BorderBrush="Transparent" Padding="7,10"><ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/></Border><ControlTemplate.Triggers><Trigger Property="IsChecked" Value="True"><Setter TargetName="B" Property="Background" Value="#263449"/><Setter TargetName="B" Property="BorderBrush" Value="#39546B"/><Setter Property="Foreground" Value="#56D8F1"/></Trigger><Trigger Property="IsMouseOver" Value="True"><Setter Property="Foreground" Value="#EDF4FD"/></Trigger><Trigger Property="IsKeyboardFocused" Value="True"><Setter TargetName="B" Property="BorderBrush" Value="#56D8F1"/></Trigger></ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter>
  </Style>
  <Style TargetType="ComboBoxItem"><Setter Property="Foreground" Value="#EDF4FD"/><Setter Property="Padding" Value="10,9"/><Setter Property="Template"><Setter.Value><ControlTemplate TargetType="ComboBoxItem"><Border x:Name="B" Background="#1C2530" Padding="{TemplateBinding Padding}"><ContentPresenter/></Border><ControlTemplate.Triggers><Trigger Property="IsHighlighted" Value="True"><Setter TargetName="B" Property="Background" Value="#30465B"/></Trigger><Trigger Property="IsSelected" Value="True"><Setter Property="Foreground" Value="#56D8F1"/></Trigger></ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter></Style>
  <Style TargetType="ComboBox"><Setter Property="Foreground" Value="#EDF4FD"/><Setter Property="MinHeight" Value="38"/><Setter Property="ScrollViewer.CanContentScroll" Value="True"/>
   <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="ComboBox"><Grid><ToggleButton x:Name="Toggle" Focusable="False" IsChecked="{Binding IsDropDownOpen, Mode=TwoWay, RelativeSource={RelativeSource TemplatedParent}}"><ToggleButton.Template><ControlTemplate TargetType="ToggleButton"><Border x:Name="B" Background="#141C26" BorderBrush="#405267" BorderThickness="1" CornerRadius="7"><TextBlock Text="⌄" HorizontalAlignment="Right" Margin="0,0,12,0" VerticalAlignment="Center" Foreground="#94A7BF"/></Border><ControlTemplate.Triggers><Trigger Property="IsMouseOver" Value="True"><Setter TargetName="B" Property="BorderBrush" Value="#56D8F1"/></Trigger></ControlTemplate.Triggers></ControlTemplate></ToggleButton.Template></ToggleButton><ContentPresenter Margin="10,7,32,7" Content="{TemplateBinding SelectionBoxItem}" ContentTemplate="{TemplateBinding SelectionBoxItemTemplate}" IsHitTestVisible="False" VerticalAlignment="Center"/><Popup x:Name="PART_Popup" Placement="Bottom" IsOpen="{TemplateBinding IsDropDownOpen}" AllowsTransparency="True" Focusable="False"><Border Background="#1C2530" BorderBrush="#405267" BorderThickness="1" CornerRadius="7" Padding="3" MinWidth="{Binding ActualWidth, RelativeSource={RelativeSource TemplatedParent}}"><ScrollViewer MaxHeight="260"><ItemsPresenter KeyboardNavigation.DirectionalNavigation="Contained"/></ScrollViewer></Border></Popup></Grid><ControlTemplate.Triggers><Trigger Property="IsKeyboardFocusWithin" Value="True"><Setter TargetName="Toggle" Property="Opacity" Value="0.85"/></Trigger></ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter>
  </Style>
  <Style TargetType="ScrollBar"><Setter Property="Width" Value="8"/><Setter Property="Template"><Setter.Value><ControlTemplate TargetType="ScrollBar"><Track x:Name="PART_Track" IsDirectionReversed="True"><Track.Thumb><Thumb><Thumb.Template><ControlTemplate TargetType="Thumb"><Border Background="#405267" CornerRadius="3" Margin="2,0"/></ControlTemplate></Thumb.Template></Thumb></Track.Thumb></Track></ControlTemplate></Setter.Value></Setter></Style>
 </Window.Resources>
 <Border Background="#151B22" BorderBrush="#505963" BorderThickness="1" CornerRadius="19" Padding="22,12,22,18">
  <Grid><Grid.RowDefinitions><RowDefinition Height="34"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
   <Grid x:Name="DragBar" Background="Transparent"><Grid.ColumnDefinitions><ColumnDefinition/><ColumnDefinition Width="32"/></Grid.ColumnDefinitions>
    <StackPanel Orientation="Horizontal" VerticalAlignment="Center"><Image x:Name="AppIcon" Width="16" Height="16" Margin="0,0,8,0"/><TextBlock Text="АйТи:Ритм" Foreground="#E5EDF7" FontWeight="SemiBold"/><TextBlock Text=" / подключения" Foreground="#8194AD"/></StackPanel>
    <Button x:Name="Close" Grid.Column="1" Content="×" Background="Transparent" BorderThickness="0" Padding="0" FontSize="20" ToolTip="Закрыть без сохранения"/>
   </Grid>
   <StackPanel Grid.Row="1" Margin="0,18,0,18"><TextBlock Text="Ваш рабочий ритм" FontSize="25" FontWeight="SemiBold"/><TextBlock Text="Подключите свои инструменты. Остальное — по желанию." Style="{StaticResource Hint}" Margin="0,5,0,0"/></StackPanel>
   <Border Grid.Row="2" Background="#11171F" CornerRadius="10" Padding="3" Margin="0,0,0,18"><UniformGrid Columns="5">
    <RadioButton x:Name="NavCodex" GroupName="Pages" Content="Codex" Tag="Codex" IsChecked="True"/>
    <RadioButton x:Name="NavClaude" GroupName="Pages" Content="Claude" Tag="Claude"/>
    <RadioButton x:Name="NavCalendar" GroupName="Pages" Content="Календарь" Tag="Calendar"/>
    <RadioButton x:Name="NavCube" GroupName="Pages" Content="Кубик" Tag="Cube"/>
    <RadioButton x:Name="NavView" GroupName="Pages" Content="Вид" Tag="View"/>
   </UniformGrid></Border>
   <ScrollViewer x:Name="PageScroll" Grid.Row="3" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled" Padding="0,0,9,0" Focusable="False"><Grid>
    <StackPanel x:Name="PageView" Visibility="Collapsed">
     <Border Style="{StaticResource Card}"><StackPanel>
      <TextBlock Text="БЛОКИ ПАНЕЛИ" Foreground="#56D8F1" FontSize="11" FontWeight="SemiBold"/>
      <TextBlock Text="Оставьте то, что нужно" FontSize="17" FontWeight="SemiBold" Margin="0,12,0,8"/>
      <TextBlock Text="Скрытие блока сохраняет подключение и доступы. Кубик продолжает работать независимо от вида панели." Style="{StaticResource Hint}"/>
      <CheckBox x:Name="ViewCalendar" Content="Календарь и ближайшая встреча" Margin="0,20,0,14"/>
      <CheckBox x:Name="ViewSessions" Content="Список сессий" Margin="0,0,0,14"/>
      <CheckBox x:Name="ViewLimits" Content="Лимиты · неделя и 5 часов" Margin="0,0,0,14"/>
      <CheckBox x:Name="ViewUsage" Content="Расход токенов"/>
      <TextBlock Text="Без подключённого календаря его карточка не появляется." Style="{StaticResource Hint}" FontSize="11" Margin="0,16,0,0"/>
     </StackPanel></Border>
     <Border Style="{StaticResource Card}"><StackPanel>
      <TextBlock Text="КОМПАКТНОСТЬ" Foreground="#94A7BF" FontSize="11" FontWeight="SemiBold"/>
      <CheckBox x:Name="ViewCompactUsage" Content="Показывать расход компактной строкой" Margin="0,16,0,16"/>
      <CheckBox x:Name="ViewAutoHeight" Content="Подбирать высоту под видимые блоки"/>
      <TextBlock Text="Можно скрыть всё: останется заголовок с настройками. Ширина уменьшается до 260." Style="{StaticResource Hint}" FontSize="11" Margin="0,14,0,0"/>
     </StackPanel></Border>
    </StackPanel>
    <StackPanel x:Name="PageCodex">
     <Border Style="{StaticResource Card}"><StackPanel>
      <TextBlock Text="CODEX" Foreground="#56D8F1" FontSize="11" FontWeight="SemiBold"/>
      <CheckBox x:Name="Codex" Content="Показывать сессии Codex" FontSize="16" FontWeight="SemiBold" Margin="0,15,0,12"/>
      <TextBlock x:Name="DetectionCodex" Style="{StaticResource Hint}"/>
      <TextBlock Text="Войдите в Codex обычным способом и начните сессию. Ритм найдёт её журналы на этом компьютере." Style="{StaticResource Hint}" Margin="0,9,0,0"/>
      <StackPanel x:Name="CodexFields">
       <CheckBox x:Name="Limits" Content="Показывать доступную квоту аккаунта" Margin="0,18,0,0"/>
       <TextBlock Text="Папка профиля Codex" Style="{StaticResource Caption}"/><TextBox x:Name="CodexHome" ToolTip="Пусто — профиль текущего пользователя"/>
       <TextBlock Text="Пусто — найдём ваш профиль автоматически." Style="{StaticResource Hint}" FontSize="11" Margin="0,5,0,0"/>
       <TextBlock Text="Путь к codex.exe" Style="{StaticResource Caption}"/><TextBox x:Name="CodexExe" ToolTip="Пусто — найти автоматически"/>
       <TextBlock Text="Укажите путь, только если автоматический поиск не сработал." Style="{StaticResource Hint}" FontSize="11" Margin="0,5,0,0"/>
      </StackPanel>
     </StackPanel></Border>
     <TextBlock Text="Ритм показывает сессии и расход. Вход в аккаунт остаётся в Codex." Style="{StaticResource Hint}" Margin="5,0,10,12"/>
    </StackPanel>
    <StackPanel x:Name="PageClaude" Visibility="Collapsed">
     <Border Style="{StaticResource Card}"><StackPanel>
      <TextBlock Text="CLAUDE CODE" Foreground="#BAABFF" FontSize="11" FontWeight="SemiBold"/>
      <CheckBox x:Name="Claude" Content="Показывать сессии Claude" FontSize="16" FontWeight="SemiBold" Margin="0,15,0,12"/>
      <TextBlock x:Name="DetectionClaude" Style="{StaticResource Hint}"/>
      <StackPanel x:Name="ClaudeFields">
       <TextBlock Text="Источник сессий" Style="{StaticResource Caption}"/><ComboBox x:Name="ClaudeSource"><ComboBoxItem Content="Мой локальный Claude Code" Tag="local"/><ComboBoxItem Content="Внешний сборщик JSON" Tag="external"/></ComboBox>
       <StackPanel x:Name="ClaudeExternal"><TextBlock Text="Команда сборщика · JSON-массив" Style="{StaticResource Caption}"/><PasswordBox x:Name="ClaudeCommand"/><TextBlock Text="Пусто — сохранить ранее настроенную команду." Style="{StaticResource Hint}" FontSize="11" Margin="0,6,0,0"/></StackPanel>
       <StackPanel x:Name="ClaudeLocal"><TextBlock Text="Папка профиля Claude" Style="{StaticResource Caption}"/><TextBox x:Name="ClaudeHome" ToolTip="Пусто — профиль текущего пользователя"/><TextBlock Text="Пусто — найдём профиль сами. Для WSL укажите папку .claude через \\wsl.localhost." Style="{StaticResource Hint}" FontSize="11" Margin="0,6,0,0"/></StackPanel>
      </StackPanel>
     </StackPanel></Border>
     <TextBlock Text="Сначала войдите в Claude Code обычным способом. Точная квота подписки может быть недоступна; расход токенов её не заменяет." Style="{StaticResource Hint}" Margin="5,0,10,12"/>
    </StackPanel>
    <StackPanel x:Name="PageCalendar" Visibility="Collapsed">
     <Border Style="{StaticResource Card}"><StackPanel>
      <TextBlock Text="КАЛЕНДАРЬ · ПО ЖЕЛАНИЮ" Foreground="#99ADA9" FontSize="11" FontWeight="SemiBold"/>
      <CheckBox x:Name="Calendar" Content="Подключить мой календарь" FontSize="16" FontWeight="SemiBold" Margin="0,15,0,12"/>
      <TextBlock Text="Ближайшая встреча и напоминания в панели. Только чтение — Ритм не меняет события." Style="{StaticResource Hint}"/>
      <StackPanel x:Name="CalendarFields">
       <TextBlock Text="Способ подключения" Style="{StaticResource Caption}"/><ComboBox x:Name="Kind"><ComboBoxItem Content="Google / Яндекс / другой iCal" Tag="ical"/><ComboBoxItem Content="Яндекс / другой CalDAV" Tag="caldav"/><ComboBoxItem Content="1С / другая публикация OData" Tag="odata"/><ComboBoxItem Content="Внешний сборщик JSON" Tag="external"/></ComboBox>
       <TextBlock Text="Название календаря" Style="{StaticResource Caption}"/><TextBox x:Name="CalendarName" ToolTip="Например, Рабочий календарь"/>
       <TextBlock Text="Часовой пояс · IANA" Style="{StaticResource Caption}"/><TextBox x:Name="Timezone"/>
       <StackPanel x:Name="CalendarExternal"><TextBlock Text="Команда сборщика · JSON-массив" Style="{StaticResource Caption}"/><PasswordBox x:Name="CalendarCommand"/></StackPanel>
       <StackPanel x:Name="CalendarDirect">
        <TextBlock Text="Личная HTTPS-ссылка iCal / адрес CalDAV или OData" Style="{StaticResource Caption}"/><PasswordBox x:Name="CalendarUrl"/>
        <TextBlock Text="Логин · если нужен источнику" Style="{StaticResource Caption}"/><TextBox x:Name="Username"/>
        <TextBlock Text="Пароль приложения / личной публикации" Style="{StaticResource Caption}"/><PasswordBox x:Name="Password"/>
       </StackPanel>
       <StackPanel x:Name="ODataFields"><TextBlock Text="Соответствие полей OData · JSON" Style="{StaticResource Caption}"/><TextBox x:Name="Mapping" TextWrapping="Wrap" AcceptsReturn="True" MinHeight="64"/><TextBlock Text="Нужен ограниченный запрос к JSON-коллекции и собственные права чтения. Поля зависят от вашей конфигурации." Style="{StaticResource Hint}" FontSize="11" Margin="0,7,0,0"/></StackPanel>
       <TextBlock Text="Ссылки и пароли зашифрованы Windows для вашего пользователя. Пустые поля сохраняют прежние доступы. Если выключить календарь и сохранить, его доступы будут удалены." Style="{StaticResource Hint}" FontSize="11" Margin="0,16,0,0"/>
      </StackPanel>
     </StackPanel></Border>
     <TextBlock Text="Без календаря Ритм продолжит показывать сессии и расход токенов." Style="{StaticResource Hint}" Margin="5,0,10,12"/>
    </StackPanel>
    <StackPanel x:Name="PageCube" Visibility="Collapsed">
     <Border Style="{StaticResource Card}"><StackPanel>
      <TextBlock Text="КУБИК · ПО ЖЕЛАНИЮ" Foreground="#FFD374" FontSize="11" FontWeight="SemiBold"/>
      <CheckBox x:Name="Cube" Content="Выводить Ритм на кубик" FontSize="16" FontWeight="SemiBold" Margin="0,15,0,12"/>
      <TextBlock Text="Сессии, лимиты и встречи на отдельном экране. В новой установке вывод выключен." Style="{StaticResource Hint}"/>
      <StackPanel x:Name="CubeFields">
       <TextBlock Text="Адрес устройства в локальной сети · IPv4" Style="{StaticResource Caption}"/><TextBox x:Name="CubeHost"/>
       <TextBlock Text="Поворот экрана" Style="{StaticResource Caption}"/><ComboBox x:Name="Rotation"><ComboBoxItem Content="0"/><ComboBoxItem Content="90"/><ComboBoxItem Content="180"/><ComboBoxItem Content="270"/></ComboBox>
       <CheckBox x:Name="Titles" Content="Разрешить названия встреч на кубике" Margin="0,18,0,0"/>
       <TextBlock Text="На устройство отправляются картинки метрик. Вывод заменяет текущую картинку и отключает автослайдшоу устройства." Style="{StaticResource Hint}" FontSize="11" Margin="0,12,0,0"/>
      </StackPanel>
     </StackPanel></Border>
     <Border Style="{StaticResource Card}" Background="#19222C"><StackPanel>
      <TextBlock Text="Подобрать кубик" FontSize="15" FontWeight="SemiBold"/>
      <TextBlock Text="Совместимы HelloCubic-Lite / SmallTV-Ultra со штатной прошивкой." Style="{StaticResource Hint}" Margin="0,8,0,12"/>
      <TextBlock><Hyperlink x:Name="CubeLink" NavigateUri="https://geekmagic.com/" Foreground="#56D8F1" TextDecorations="None">Решения GeekMagic ↗</Hyperlink></TextBlock>
     </StackPanel></Border>
    </StackPanel>
   </Grid></ScrollViewer>
   <StackPanel Grid.Row="4" Margin="0,14,0,0"><TextBlock x:Name="Status" Foreground="#FF9A9F" Margin="0,0,0,8" Visibility="Collapsed"/>
    <Grid><Grid.ColumnDefinitions><ColumnDefinition/><ColumnDefinition Width="Auto"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
     <TextBlock Text="Личные подключения&#10;остаются на этом компьютере" Style="{StaticResource Hint}" FontSize="10" VerticalAlignment="Center" Margin="0,0,15,0"/>
     <Button x:Name="Cancel" Grid.Column="1" Content="Отмена" Background="Transparent" BorderBrush="#344354" Margin="0,0,8,0" IsCancel="True"/>
     <Button x:Name="Save" Grid.Column="2" Content="Сохранить" Background="#56D8F1" Foreground="#11212B" BorderBrush="#56D8F1" FontWeight="SemiBold" IsDefault="True"/>
    </Grid>
   </StackPanel>
  </Grid>
 </Border>
</Window>
'@
$window=[Windows.Markup.XamlReader]::Load([Xml.XmlNodeReader]::new($xaml))
$controls=@{};foreach($name in @('ClaudeSource','ClaudeCommand','CalendarCommand','Codex','CodexHome','CodexExe','Limits','Claude','ClaudeHome','Calendar','Kind','CalendarName','Timezone','CalendarUrl','Username','Password','Mapping','Cube','CubeHost','Rotation','Titles','Save','Cancel','Status')){$controls[$name]=$window.FindName($name)}
$viewControls=@{calendar='ViewCalendar';sessions='ViewSessions';limits='ViewLimits';usage='ViewUsage';compact_usage='ViewCompactUsage';auto_height='ViewAutoHeight'}
foreach($name in $viewControls.Values){$controls[$name]=$window.FindName($name)}
$icon=Join-Path $PSScriptRoot 'indicators.ico'
if(Test-Path -LiteralPath $icon){$window.Icon=[Windows.Media.Imaging.BitmapFrame]::Create([Uri]$icon);$window.FindName('AppIcon').Source=$window.Icon}
$window.MaxHeight=[Windows.SystemParameters]::WorkArea.Height-24
$window.MaxWidth=[Windows.SystemParameters]::WorkArea.Width-24
$window.MinHeight=[Math]::Min($window.MinHeight,$window.MaxHeight);$window.Height=[Math]::Min($window.Height,$window.MaxHeight)
$window.MinWidth=[Math]::Min($window.MinWidth,$window.MaxWidth);$window.Width=[Math]::Min($window.Width,$window.MaxWidth)
$window.FindName('DragBar').Add_MouseLeftButtonDown({$bar=$window.FindName('DragBar');if($_.GetPosition($bar).X -lt ($bar.ActualWidth-38)){$window.DragMove()}})
$window.FindName('Close').Add_Click({$window.Close()})
function SelectConnectionPage($page){
 foreach($name in @('Codex','Claude','Calendar','Cube','View')){$window.FindName('Page'+$name).Visibility=if($name -eq $page){'Visible'}else{'Collapsed'}}
 $window.FindName('PageScroll').ScrollToTop()
}
foreach($name in @('Codex','Claude','Calendar','Cube','View')){$window.FindName('Nav'+$name).Add_Checked({param($sender,$eventArgs) SelectConnectionPage ([string]$sender.Tag)})}
function UpdateConnectionFields{
 foreach($name in @('Codex','Claude','Calendar','Cube')){$window.FindName($name+'Fields').Visibility=if($controls[$name].IsChecked){'Visible'}else{'Collapsed'}}
 $external=$controls.ClaudeSource.SelectedItem.Tag -eq 'external'
 $window.FindName('ClaudeExternal').Visibility=if($external){'Visible'}else{'Collapsed'}
 $window.FindName('ClaudeLocal').Visibility=if($external){'Collapsed'}else{'Visible'}
 $kind=[string]$controls.Kind.SelectedItem.Tag
 $window.FindName('CalendarExternal').Visibility=if($kind -eq 'external'){'Visible'}else{'Collapsed'}
 $window.FindName('CalendarDirect').Visibility=if($kind -eq 'external'){'Collapsed'}else{'Visible'}
 $window.FindName('ODataFields').Visibility=if($kind -eq 'odata'){'Visible'}else{'Collapsed'}
}
foreach($name in @('Codex','Claude','Calendar','Cube')){$controls[$name].Add_Checked({UpdateConnectionFields});$controls[$name].Add_Unchecked({UpdateConnectionFields})}
$controls.Kind.Add_SelectionChanged({UpdateConnectionFields});$controls.ClaudeSource.Add_SelectionChanged({UpdateConnectionFields})
$window.FindName('CubeLink').Add_RequestNavigate({param($sender,$eventArgs)
 # Fixed public destination; no connection values are put in the URL.
 if(-not $SelfTest){Start-Process -FilePath 'https://geekmagic.com/'}
 $eventArgs.Handled=$true
})
$configPath=Join-Path $dataRoot 'connections.json'
$discoveryPath=Join-Path $dataRoot 'discovery.json'
$window.FindName('DetectionCodex').Text='Журналы будут найдены при запуске панели.';$window.FindName('DetectionClaude').Text='Журналы будут найдены при запуске панели.'
if(Test-Path -LiteralPath $discoveryPath){$found=Get-Content -LiteralPath $discoveryPath -Raw -Encoding UTF8|ConvertFrom-Json;$codexFound=if($found.codex_journals){'Журналы Codex найдены на этом компьютере.'}elseif($found.codex_installed){'Codex установлен. Запустите первую сессию.'}else{'Codex пока не найден.'};$claudeFound=if($found.claude_external){'Настроен внешний источник сессий Claude.'}elseif($found.claude_journals){'Журналы Claude Code найдены на этом компьютере.'}elseif($found.claude_installed){'Claude Code установлен. Запустите первую сессию.'}else{'Claude Code пока не найден.'};$window.FindName('DetectionCodex').Text=$codexFound;$window.FindName('DetectionClaude').Text=$claudeFound}
if(Test-Path -LiteralPath $configPath){$config=Get-Content -LiteralPath $configPath -Raw -Encoding UTF8|ConvertFrom-Json}else{$config=$null}
foreach($key in $viewControls.Keys){$controls[$viewControls[$key]].IsChecked=if($null -ne $config.view.$key){[bool]$config.view.$key}else{$true}}
$controls.Codex.IsChecked=if($config){[bool]$config.codex.enabled}else{$true};$controls.Limits.IsChecked=if($config){[bool]$config.codex.limits}else{$true}
$controls.Claude.IsChecked=if($config){[bool]$config.claude.enabled}else{$true};$controls.Calendar.IsChecked=[bool]$config.calendar.enabled;$controls.Cube.IsChecked=[bool]$config.cube.enabled
$controls.CodexHome.Text=[string]$config.codex.home;$controls.CodexExe.Text=[string]$config.codex.executable;$controls.ClaudeHome.Text=[string]$config.claude.home
$controls.CalendarName.Text=[string]$config.calendar.name;$controls.Timezone.Text=if($config.calendar.timezone){$config.calendar.timezone}else{'Europe/Moscow'}
$controls.ClaudeSource.SelectedIndex=0;foreach($item in $controls.ClaudeSource.Items){if($item.Tag -eq $config.claude.source){$controls.ClaudeSource.SelectedItem=$item}}
$controls.Kind.SelectedIndex=0;foreach($item in $controls.Kind.Items){if($item.Tag -eq $config.calendar.kind){$controls.Kind.SelectedItem=$item}}
$controls.Mapping.Text=if($config.calendar.mapping){$config.calendar.mapping|ConvertTo-Json -Compress}else{'{"id":"id","subject":"subject","start":"start","end":"end","url":"url"}'}
$script:initialMapping=$controls.Mapping.Text|ConvertFrom-Json
$controls.CubeHost.Text=[string]$config.cube.host;$controls.Titles.IsChecked=[bool]$config.cube.show_titles;$controls.Rotation.SelectedIndex=0
foreach($item in $controls.Rotation.Items){if([string]$item.Content -eq [string]$config.cube.rotation){$controls.Rotation.SelectedItem=$item}}
UpdateConnectionFields
$controls.Cancel.Add_Click({$window.Close()})
$controls.Save.Add_Click({
 try{
  $controls.Status.Text='';$controls.Status.Visibility='Collapsed'
  $values=@{
   codex=@{enabled=[bool]$controls.Codex.IsChecked;home=$controls.CodexHome.Text.Trim();executable=$controls.CodexExe.Text.Trim();limits=[bool]$controls.Limits.IsChecked}
   claude=@{enabled=[bool]$controls.Claude.IsChecked;home=$controls.ClaudeHome.Text.Trim();source=[string]$controls.ClaudeSource.SelectedItem.Tag}
   calendar=@{enabled=[bool]$controls.Calendar.IsChecked;kind=[string]$controls.Kind.SelectedItem.Tag;name=$controls.CalendarName.Text.Trim();timezone=$controls.Timezone.Text.Trim();mapping=$(if($controls.Calendar.IsChecked -and $controls.Kind.SelectedItem.Tag -eq 'odata'){$controls.Mapping.Text|ConvertFrom-Json}else{$initialMapping})}
   cube=@{enabled=[bool]$controls.Cube.IsChecked;host=$controls.CubeHost.Text.Trim();rotation=[int][string]$controls.Rotation.SelectedItem.Content;show_titles=[bool]$controls.Titles.IsChecked}
   view=@{calendar=[bool]$controls.ViewCalendar.IsChecked;sessions=[bool]$controls.ViewSessions.IsChecked;limits=[bool]$controls.ViewLimits.IsChecked;usage=[bool]$controls.ViewUsage.IsChecked;compact_usage=[bool]$controls.ViewCompactUsage.IsChecked;auto_height=[bool]$controls.ViewAutoHeight.IsChecked}
   secrets=@{claude_command=$(if($controls.ClaudeCommand.Password){ConvertFrom-Json -InputObject $controls.ClaudeCommand.Password}else{$null});calendar_command=$(if($controls.CalendarCommand.Password){ConvertFrom-Json -InputObject $controls.CalendarCommand.Password}else{$null});calendar_url=$controls.CalendarUrl.Password.Trim();calendar_username=$controls.Username.Text.Trim();calendar_password=$controls.Password.Password}
  }
  $python=$env:RHYTHM_CORE_EXE
  $start=[Diagnostics.ProcessStartInfo]::new();$start.FileName=$python;$start.Arguments=$env:RHYTHM_CORE_PREFIX+' --configure-stdin';$start.UseShellExecute=$false;$start.CreateNoWindow=$true;$start.RedirectStandardInput=$true;$start.RedirectStandardOutput=$true;$start.RedirectStandardError=$true
  $process=[Diagnostics.Process]::Start($start);$payload=[Text.Encoding]::UTF8.GetBytes(($values|ConvertTo-Json -Depth 8 -Compress));$process.StandardInput.BaseStream.Write($payload,0,$payload.Length);$process.StandardInput.BaseStream.Close();$output=$process.StandardOutput.ReadToEnd();$errorText=$process.StandardError.ReadToEnd();$process.WaitForExit()
  if($process.ExitCode -ne 0){$controls.Status.Visibility='Visible';$controls.Status.Text='Проверьте поля подключения. Нужен HTTPS-адрес календаря; для кубика — локальный IPv4.';return}
  $window.Close()
 }catch{if($SelfTest){throw};$controls.Status.Visibility='Visible';$controls.Status.Text='Не удалось сохранить. Проверьте формат полей подключения.'}
})
if($ValidateOnly){Write-Output 'Connections dialog parsed; no secrets read or settings changed.'}
elseif($SelfTest){
 if(-not $config -and ($controls.Calendar.IsChecked -or $controls.Cube.IsChecked)){throw 'Optional connections must default to off'}
 if(-not $config){foreach($name in $viewControls.Values){if(-not $controls[$name].IsChecked){throw 'New view controls must default to enabled'}}}
 if($window.FindName('CubeLink').NavigateUri.AbsoluteUri -ne 'https://geekmagic.com/'){throw 'Unexpected cube link'}
 $window.Show();$window.UpdateLayout()
 function SaveSettingsPreview($name){
  $window.UpdateLayout()
  $bitmap=[Windows.Media.Imaging.RenderTargetBitmap]::new([int]$window.ActualWidth,[int]$window.ActualHeight,96,96,[Windows.Media.PixelFormats]::Pbgra32)
  $bitmap.Render($window);$encoder=[Windows.Media.Imaging.PngBitmapEncoder]::new();$encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bitmap))
  $file=[IO.File]::Create((Join-Path $dataRoot ('settings-'+$name+'.png')));try{$encoder.Save($file)}finally{$file.Dispose()}
 }
 foreach($name in @('Codex','Claude','Calendar','Cube','View')){
  $window.FindName('Nav'+$name).IsChecked=$true
  foreach($other in @('Codex','Claude','Calendar','Cube','View')){if(($window.FindName('Page'+$other).Visibility -eq 'Visible') -ne ($name -eq $other)){throw 'Section navigation failed'}}
  SaveSettingsPreview $name
 }
 if($window.FindName('CubeFields').Visibility -ne 'Collapsed'){throw 'Disabled cube fields must be hidden'}
 $window.FindName('NavCube').IsChecked=$true
 if(-not $window.FindName('CubeLink').Parent.IsVisible){throw 'Cube link must stay visible while output is off'}
 $controls.Cube.IsChecked=$true;if($window.FindName('CubeFields').Visibility -ne 'Visible'){throw 'Enabled cube fields missing'}
 SaveSettingsPreview 'Cube-on';$controls.Cube.IsChecked=$false
 $window.FindName('NavCalendar').IsChecked=$true;$controls.Calendar.IsChecked=$true
 foreach($item in $controls.Kind.Items){
  $controls.Kind.SelectedItem=$item;$kind=[string]$item.Tag
  if(($window.FindName('CalendarExternal').Visibility -eq 'Visible') -ne ($kind -eq 'external')){throw 'Wrong calendar command visibility'}
  if(($window.FindName('ODataFields').Visibility -eq 'Visible') -ne ($kind -eq 'odata')){throw 'Wrong OData mapping visibility'}
  SaveSettingsPreview ('Calendar-'+$kind)
 }
 $controls.ClaudeSource.SelectedIndex=1;if($window.FindName('ClaudeLocal').Visibility -ne 'Collapsed' -or $window.FindName('ClaudeExternal').Visibility -ne 'Visible'){throw 'Wrong Claude source visibility'}
 $controls.ClaudeSource.SelectedIndex=0
 $window.Width=$window.MinWidth;$window.Height=$window.MinHeight;$window.FindName('NavCube').IsChecked=$true;SaveSettingsPreview 'compact'
 $controls.CodexHome.Text=Join-Path $dataRoot 'fixture-codex';$controls.ClaudeHome.Text=Join-Path $dataRoot 'fixture-claude';$controls.Limits.IsChecked=$false;$controls.Calendar.IsChecked=$false;$controls.Cube.IsChecked=$false
 $controls.Cube.IsChecked=$true;$controls.CubeHost.Text='8.8.8.8'
 $controls.Save.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Primitives.ButtonBase]::ClickEvent))
 if(-not $controls.Status.Text -or $controls.Status.Visibility -ne 'Visible'){throw 'Invalid connection must show an inline error'}
 $controls.Cube.IsChecked=$false;$controls.CubeHost.Text=''
 # Hidden OData text must not prevent saving an unrelated/disabled connection.
 $controls.Mapping.Text='not-json'
 $controls.ViewCalendar.IsChecked=$false;$controls.ViewSessions.IsChecked=$false;$controls.ViewUsage.IsChecked=$false
 $controls.Save.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Primitives.ButtonBase]::ClickEvent))
 if($controls.Status.Text -or -not (Test-Path -LiteralPath $configPath)){throw 'Settings save bridge failed'}
 $saved=Get-Content -LiteralPath $configPath -Raw -Encoding UTF8|ConvertFrom-Json
 if($saved.view.calendar -or $saved.view.sessions -or $saved.view.usage -or -not $saved.view.limits){throw 'Visibility switches did not round-trip through the settings bridge'}
 Write-Output 'Settings theme, navigation, optional defaults, source fields, inline error, previews and isolated save bridge passed.'
}else{[void]$window.ShowDialog()}
