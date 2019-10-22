module Components.SolveProblem (component) where

import Prelude

import Components.ApplyRuleModal as RuleDlg
import Components.NewExprButton as NewBtn
import Data.Array (foldl, intercalate)
import Data.Array as Array
import Data.Environment (AssumptionStack, Environment)
import Data.Environment as Env
import Data.Expressions (Expr)
import Data.FitchRules as Fitch
import Data.List (List, (:))
import Data.List as List
import Data.Maybe (Maybe(..))
import Data.Problem (Problem)
import Data.Route as R
import Data.Rules (Rule, RuleInstance)
import Data.Rules as Rules
import Data.Scope (Scope)
import Data.Scope as Scope
import Data.Symbol (SProxy(..))
import Data.Tuple (Tuple(..))
import Effect.Class (class MonadEffect)
import Halogen (ClassName(..))
import Halogen as H
import Halogen.HTML (HTML)
import Halogen.HTML as HH
import Halogen.HTML.Events as HE
import Halogen.HTML.Properties as HP

type State =
  { showRuleModal :: Maybe Rule
  , problem :: Problem
  , history :: List { item :: HistoryItem, stack :: AssumptionStack }
  }

data Action
  = ShowRuleModal Rule
  | AddConclusion Expr
  | HandleRuleModal RuleDlg.Message
  | HandleAssumeNew NewBtn.Message
  | ChangeProblem Problem

type ChildSlots =
  ( newRuleModal :: RuleDlg.Slot Unit
  , assumeNew ::NewBtn.Slot Unit
  )

_newRuleModal :: SProxy "newRuleModal"
_newRuleModal = SProxy

_assumeNew :: SProxy "assumeNew"
_assumeNew = SProxy

component :: forall q o m. MonadEffect m => H.Component HH.HTML q Problem o m
component =
  H.mkComponent
    { initialState
    , render
    , eval: H.mkEval $ H.defaultEval { handleAction = handleAction, receive = Just <<< ChangeProblem }
    }

initialState :: Problem -> State
initialState problem =
  flip (foldl (flip addPremisse)) problem.premisses
  { showRuleModal: Nothing
  , problem
  , history: List.Nil
  }

render :: forall m. MonadEffect m => State -> H.ComponentHTML Action ChildSlots m
render state = HH.div_
  [ case state.showRuleModal of
      Just rule -> HH.slot _newRuleModal unit 
        RuleDlg.component 
          { scope: curScope
          , rule
          } 
        (Just <<< HandleRuleModal)
      Nothing -> HH.text "" 
  , HH.div_
    [ showGoal state.problem
    , showFound state
    , showHistory (List.toUnfoldable $ List.reverse $ map _.item state.history) 
    , showAssumeNew
    , showRuleButtons curScope Fitch.rules
    ]
  ]
  where
  curScope = currentScope state
  showAssumeNew =
    HH.div
      [ HP.class_ (ClassName "box") ] 
      [ HH.h1 [ HP.class_ (ClassName "subtitle") ] [ HH.text "assume" ]
      , HH.slot _assumeNew unit NewBtn.component unit (Just <<< HandleAssumeNew)
      , showImplButtons state
      ]

handleAction ::forall o m. Action -> H.HalogenM State Action ChildSlots o m Unit
handleAction = case _ of
  ChangeProblem p -> do
    let newState = initialState p
    H.put newState
  ShowRuleModal rule ->
    H.modify_ (\st -> st { showRuleModal = Just rule })
  HandleRuleModal RuleDlg.Canceled ->
    H.modify_ (\st -> st { showRuleModal = Nothing })
  HandleRuleModal (RuleDlg.NewRule r) ->
    H.modify_ (\st -> useRule r $ st { showRuleModal = Nothing })
  HandleAssumeNew (NewBtn.NewExpr expr) ->
    H.modify_ (addAssumption expr)
  AddConclusion expr ->
    H.modify_ (addConclusion expr)

showRuleButtons :: forall w. Scope -> Array Rule -> HTML w Action
showRuleButtons _ rules | Array.null rules = HH.text ""
showRuleButtons scope rules =
  HH.div
    [ HP.class_ (ClassName "box") ] 
    [ HH.h1 [ HP.class_ (ClassName "subtitle") ] [ HH.text "rules" ]
    , HH.div
      [ HP.class_ (ClassName "buttons is-marginless") ]
      (map showRuleButton rules)
    ]
  where
  showRuleButton rule = HH.button 
    [ HP.class_ (ClassName "button") 
    , HP.disabled (not $ Rules.isUsableWith rule.ruleRecipe scope)
    , HE.onClick (\_ -> Just (ShowRuleModal rule))
    ] 
    [ HH.text rule.ruleName ]

showImplButtons :: forall w. State -> HTML w Action
showImplButtons state | Env.stackDepth (currentStack state) <= 0 = HH.text ""
showImplButtons state =
  HH.div
    [ HP.class_ (ClassName "box") ] 
    [ HH.h1 [ HP.class_ (ClassName "subtitle") ] [ HH.text "results" ]
    , HH.div
      [ HP.class_ (ClassName "buttons is-marginless") ]
      (map showImplButton $ Scope.toArray $ currentScope state)
    ]
  where
  showImplButton expr = HH.button 
    [ HP.class_ (ClassName "button") 
    , HE.onClick (\_ -> Just $ AddConclusion expr)
    ]
    [ HH.text $ "=> " <> show expr ]

showGoal :: forall w i. Problem -> HTML w i
showGoal problem =
  HH.div
    [ HP.class_ (ClassName "box") ] 
    [ HH.h2 [ HP.class_ (ClassName "subtitle") ] [ HH.text "Goal" ]
    , HH.h1 [ HP.class_ (ClassName "title") ] [ HH.text $ show problem.goal ]
    , HH.h3 
      [ HP.class_ (ClassName "subtitle") ]
      [ HH.text $ "premisses: " 
      , HH.strong_ [ HH.text $ intercalate ", " (map show problem.premisses) ]
      ]
    , HH.a [ R.routeHref R.Home ] [ HH.text "back to problems.." ]
    ]

showFound :: forall w i. State -> HTML w i
showFound state | Scope.inScope (currentScope state) state.problem.goal =
  HH.div
    [ HP.class_ (ClassName "notification is-success") ]
    [ HH.h1 [ HP.class_ (ClassName "title")] [ HH.text "YOU did it!!!"] ]
showFound _ =
  HH.div
    [ HP.class_ (ClassName "notification is-warning") ]
    [ HH.h2 [ HP.class_ (ClassName "subtitle")] [ HH.text "keep going - you can make it"] ]
----------------------------------------------------------------------
-- History

currentStack :: State -> AssumptionStack
currentStack state =
  case List.uncons state.history of
    Just { head, tail: _ } -> head.stack
    Nothing -> Env.NoAssumptions (initialScope state)

initialScope :: State -> Scope
initialScope state = 
  foldl Scope.include Scope.empty state.problem.premisses

currentScope :: State -> Scope
currentScope = Env.scopeOf <<< currentStack

runWith :: forall a. State -> Environment a -> Tuple a AssumptionStack
runWith state = Env.runWith (currentStack state)

addNewItem :: State -> Environment HistoryItem -> State
addNewItem state comp = 
  maybeAddNewItem state (comp >>= (pure <<< Just))

maybeAddNewItem :: State -> Environment (Maybe HistoryItem) -> State
maybeAddNewItem state comp =
  case runWith state comp of
    Tuple (Just newItem) newStack ->
      state { history = { item: newItem, stack: newStack } : state.history }
    Tuple Nothing _ -> state

data HistoryItem
  = UsedRule { ruleInstance :: RuleInstance, newFact :: Expr }
  | AddedPremisse { premisse :: Expr }
  | NewAssumption { assumption :: Expr }
  | FoundImplication { newFact :: Expr }

useRule :: { ruleInstance :: RuleInstance, newFact :: Expr } -> State -> State
useRule r state = addNewItem state $ do
  _ <- Env.tryApply r.ruleInstance
  pure $ UsedRule r

addPremisse :: Expr -> State -> State
addPremisse prem state = addNewItem state $ do
  _ <- Env.addExpr prem
  pure $ AddedPremisse { premisse: prem }

addAssumption :: Expr -> State -> State
addAssumption assumption state = addNewItem state $ do
  _ <- Env.assume assumption
  pure $ NewAssumption { assumption }

addConclusion :: Expr -> State -> State
addConclusion conclusion state = maybeAddNewItem state $ do
  found <- Env.introduceImplication conclusion
  pure $ map (\newFact -> FoundImplication { newFact }) found

showHistory :: forall w i. Array HistoryItem -> HTML w i
showHistory items =
  HH.div
    [ HP.class_ (ClassName "box history") ] 
    [ HH.h1 [ HP.class_ (ClassName "subtitle") ] [ HH.text "history" ]
    , HH.ol_ (let res = go [] items in res.list)
    ]
  where
  go acc hs =
    case Array.uncons hs of
      Nothing -> { add: HH.text "", rest: [], list: acc }
      Just { head, tail } -> 
        case head of
          (AddedPremisse p) ->
            let new = HH.li_ [ HH.span_ [ HH.text "premisse: ", HH.strong_ [ HH.text $ show p.premisse ] ] ]
            in go (Array.snoc acc new) tail
          (UsedRule r) ->
            let 
              new = HH.li_ 
                [ HH.span_ 
                  [ HH.strong_ [ HH.text $ show r.newFact ] 
                  , HH.text " - "
                  , HH.em_ [ HH.text r.ruleInstance.description ] 
                  ]
                ] 
            in go (Array.snoc acc new) tail
          (NewAssumption a) ->
            let new = HH.li_ [ HH.span_ [ HH.text "assume: ", HH.strong_ [ HH.text $ show a.assumption ] ] ]
                res = go [] tail
                addSub = if Array.null res.list then identity else flip Array.snoc (HH.li_ [HH.ol_ res.list])
            in go (Array.snoc (addSub (Array.snoc acc new)) res.add) res.rest
          (FoundImplication impl) ->
            let new = HH.li_ [ HH.span_ [ HH.strong_ [ HH.text $ show impl.newFact ] ] ]
            in { add: new, rest: tail, list: acc }
