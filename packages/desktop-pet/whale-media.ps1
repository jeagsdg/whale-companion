# Presentation images are small and bounded. Clipboard exports use the original PNG.
function Get-PetPosePath([string]$Key){
  $aliases=@{success='ok';failure='err';'meme-heart'='valentine';'meme-shock'='meme-omg';'idle-cute'='idle';waiting='wait';'meme-music'='daily-gaming';celebrate='game-happy';'meme-broke'='daily-melt';'meme-no'='no';'meme-yes'='ok'}
  if($aliases.ContainsKey($Key)){$Key=$aliases[$Key]}
  if($script:catalog.bindings){$binding=$script:catalog.bindings.PSObject.Properties[$Key];if($binding -and [string]$binding.Value -match '^[a-z0-9][a-z0-9-]{0,63}$'){$Key=[string]$binding.Value}}
  if($Key -notmatch '^[a-z0-9][a-z0-9-]{0,63}$'){$Key='idle'}
  $path=Join-Path $PetHome ('assets\'+$Key+'.png')
  if(-not [IO.File]::Exists($path)){$path=Join-Path $PetHome 'assets\idle.png'}
  return $path
}
function Read-PetBitmap([string]$Path,[int]$DecodeWidth=320){
  $stream=$null
  try{
    $stream=[IO.File]::OpenRead($Path)
    $bitmap=New-Object Windows.Media.Imaging.BitmapImage;$bitmap.BeginInit()
    $bitmap.CacheOption=[Windows.Media.Imaging.BitmapCacheOption]::OnLoad
    if($DecodeWidth -gt 0){$bitmap.DecodePixelWidth=$DecodeWidth}
    $bitmap.StreamSource=$stream;$bitmap.EndInit();$bitmap.Freeze();return $bitmap
  }finally{if($stream){$stream.Dispose()}}
}
function New-PetStickerClipboardData([string]$Path){
  $bytes=[IO.File]::ReadAllBytes($Path)
  $data=New-Object Windows.DataObject
  foreach($format in @('PNG','image/png')){
    $stream=New-Object IO.MemoryStream(,$bytes)
    $data.SetData($format,$stream,$false)
  }
  $source=Read-PetBitmap $Path 512
  # Older paste targets discard DIB alpha. Give those targets a clean white
  # fallback; PNG-aware targets and file paste retain the original transparency.
  $visual=New-Object Windows.Media.DrawingVisual;$draw=$visual.RenderOpen()
  try{$rect=New-Object Windows.Rect(0,0,$source.PixelWidth,$source.PixelHeight);$draw.DrawRectangle([Windows.Media.Brushes]::White,$null,$rect);$draw.DrawImage($source,$rect)}finally{$draw.Close()}
  $fallback=New-Object Windows.Media.Imaging.RenderTargetBitmap($source.PixelWidth,$source.PixelHeight,96,96,[Windows.Media.PixelFormats]::Pbgra32)
  $fallback.Render($visual);$fallback.Freeze();$data.SetImage($fallback)
  $data.SetData([Windows.DataFormats]::FileDrop,[string[]]@($Path),$false)
  return $data
}
