{-# LANGUAGE TemplateHaskell #-}
module Main where

import Reflex.Dom
import Data.FileEmbed
import Utils.Vars
import Utils.ABT
import Dependent.Unification.Elaborator
import Dependent.Unification.Elaboration
import Dependent.Core.Term
import Dependent.Core.Parser
import qualified Data.ByteString.Char8 as BS
import qualified Data.Text as T
import Control.Monad.Trans
import Data.List
import GHCJS.DOM.Document
import GHCJS.DOM.Types
import ProofCas.Backends.SFP.Status
import ProofCas.Backends.SFP.Interface

Right std = parseProgram (BS.unpack $(embedFile "std.sfp"))
Right (_, ElabState sig defs _ _ _) = runElaborator0 (elabProgram std)

parseAssm code = (\t -> (FreeVar (T.unpack n), t)) <$> parseTerm (T.unpack (T.tail code'))
  where (n, code') = T.breakOn ":" code

freeToDefinedModCtx :: Context -> ABT TermF -> ABT TermF
freeToDefinedModCtx c = freeToDefined d
  where d s
          | FreeVar s `elem` map fst c = Var (Free (FreeVar s))
          | otherwise = In (Defined s)

parseStatus code = do
  thm:prf:ctx <- let s = T.splitOn "," code
                 in if length s >= 2 then Right s else Left "not enough parts"
  ctx' <- mapM parseAssm ctx
  let ctx'' = zipWith ftdmc (inits ctx') ctx'
      ftdmc c (v, t) = (v, freeToDefinedModCtx c t)
  thm' <- freeToDefinedModCtx ctx'' <$> parseTerm (T.unpack thm)
  prf' <- freeToDefinedModCtx ctx'' <$> parseTerm (T.unpack prf)
  return (Status sig defs ctx'' thm' prf')

fromCode bodyEl c = case parseStatus c of
  Left err -> text (T.pack err)
  Right st -> sfpWidget bodyEl st


main :: IO ()
main = mainWidgetWithCss $(embedFile "term.css") $ do
  ti <- textInput def
  let newCode = tagPromptlyDyn (value ti) (keypress Enter ti)
  document <- Control.Monad.Trans.lift askDocument
  Just rawBody <- getBody document
  bodyEl <- wrapRawElement (toElement rawBody) def
  widgetHold (return ()) $ fromCode bodyEl <$> newCode
  return ()

