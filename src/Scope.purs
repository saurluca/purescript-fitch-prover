module Scope 
  ( Scope
  , empty
  , inScope
  , include
  , remove
  ) where

import Prelude

import Data.Newtype (class Newtype)
import Data.Set (Set)
import Data.Set as Set
import Expressions (Expr)

newtype Scope = Scope (Set Expr)

derive instance newtypeScope :: Newtype Scope _

empty :: Scope
empty = Scope Set.empty

inScope :: Scope -> Expr -> Boolean
inScope (Scope scope) expr = 
  expr `Set.member` scope

include :: Scope -> Expr -> Scope
include (Scope scope) expr = 
  Scope $ expr `Set.insert` scope

remove :: Scope -> Expr -> Scope
remove (Scope scope) expr =
  Scope $ expr `Set.delete` scope