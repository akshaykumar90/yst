{-
Copyright (C) 2009 John MacFarlane <jgm@berkeley.edu>

This program is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 2 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
-}

module Yst.Render (renderPage)
where
import Yst.Types
import Yst.Util
import Yst.Data
import System.Directory
import Text.Pandoc
import Text.XHtml hiding (option, (</>))
import Data.Char
import Data.List (intercalate)
import Text.StringTemplate
import Data.Maybe (fromMaybe)
import System.FilePath
import System.IO.UTF8
import Prelude hiding (readFile, putStrLn, print, writeFile)
import Data.Time
import Control.Monad

renderNav :: String -> [NavNode] -> String
renderNav targeturl nodes = renderHtmlFragment $
  ulist ! [theclass "nav"] << map (renderNavNode targeturl) nodes

renderNavNode :: String -> NavNode -> Html
renderNavNode targeturl (NavPage tit pageurl) =
  li ! attrs << hotlink pageurl << tit
    where attrs = if pageurl == targeturl
                     then [theclass "current"]
                     else []
renderNavNode targeturl (NavMenu tit nodes) =
  li ! attrs << [ toHtml $ hotlink "#" << (tit ++ " »")
                , ulist ! attrs << map (renderNavNode targeturl) nodes ]
    where active = targeturl `isInNavNodes` nodes
          attrs = if active then [theclass "active"] else []
          isInNavNodes u = any (isInNavNode u)
          isInNavNode u (NavPage _ u') = u == u'
          isInNavNode u (NavMenu _ ns) = u `isInNavNodes` ns

formatFromExtension :: FilePath -> Format
formatFromExtension f = case (map toLower $ takeExtension f) of
                             ".html"  -> HtmlFormat
                             ".xhtml" -> HtmlFormat
                             ".latex" -> LaTeXFormat
                             ".tex"   -> LaTeXFormat
                             ".context" -> ConTeXtFormat
                             ".1"     -> ManFormat
                             ".rtf"   -> RTFFormat
                             ".texi"  -> TexinfoFormat
                             ".db"    -> DocBookFormat
                             ".fodt"  -> OpenDocumentFormat
                             ".txt"   -> PlainFormat
                             ".markdown" -> PlainFormat
                             _       -> HtmlFormat
renderPage :: Site -> Page -> IO String
renderPage site page = do
  let menuHtml = renderNav (pageUrl page) (navigation site)
  let layout = fromMaybe (defaultLayout site) $ layoutFile page
  srcDir <- canonicalizePath $ sourceDir site
  g <- directoryGroup srcDir
  attrs <- forM (pageData page) $ \(k, v) -> getData v >>= \n -> return (k,n)
  todaysDate <- liftM utctDay getCurrentTime
  rawContents <-
    case sourceFile page of
          SourceFile sf   -> readFile (srcDir </> sf)
          TemplateFile tf -> do
            templ <- getTemplate tf g
            return $ render (setManyAttrib attrs templ)
  layoutTempl <- getTemplate layout g
  let format = formatFromExtension (stripStExt layout)
  let contents = converterForFormat format rawContents
  return $ render
         . setAttribute "sitetitle" (siteTitle site)
         . setAttribute "pagetitle" (pageTitle page)
         . setAttribute "gendate" todaysDate 
         . setAttribute "contents" contents
         . setAttribute "nav" menuHtml
         $ layoutTempl

converterForFormat :: Format -> String -> String
converterForFormat f =
  let reader = readMarkdown defaultParserState{stateSmart = True}
  in  case f of
       HtmlFormat          -> writeHtmlString defaultWriterOptions . reader
       LaTeXFormat         -> writeLaTeX defaultWriterOptions . reader
       PlainFormat         -> id
       ConTeXtFormat       -> writeConTeXt defaultWriterOptions . reader
       ManFormat           -> writeMan defaultWriterOptions . reader
       RTFFormat           -> writeRTF defaultWriterOptions . reader
       DocBookFormat       -> writeDocbook defaultWriterOptions . reader
       TexinfoFormat       -> writeTexinfo defaultWriterOptions . reader
       OpenDocumentFormat  -> writeOpenDocument defaultWriterOptions . reader

getTemplate :: Stringable a => String -> STGroup a -> IO (StringTemplate a)
getTemplate templateName templateGroup = do
  let template = case getStringTemplate (stripStExt templateName) templateGroup of
                       Just pt  -> pt
                       Nothing  -> error $ "Could not load template: " ++ templateName
  case checkTemplate template of
       (Just parseErrors, _, _ )       -> errorExit 17 $ "Error in template '" ++ templateName ++
                                             "': " ++ parseErrors
       (_, _, Just templatesNotFound)  -> errorExit 21 $ "Templates referenced in template '" ++ templateName ++
                                             "' not found: " ++ (intercalate ", " templatesNotFound)
       (_, _, _)                       -> return ()
  return template