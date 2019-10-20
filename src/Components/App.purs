module Components.App (component) where

import Prelude

import Components.ApplyRuleModal as RuleDlg
import Components.Button as Button
import Data.Array as Array
import Data.Either (either)
import Data.List (List, (:))
import Data.List as List
import Data.Maybe (Maybe(..), maybe)
import Data.Set (Set)
import Data.Symbol (SProxy(..))
import Data.Tuple (Tuple(..))
import Effect.Class (class MonadEffect)
import Environment (AssumptionStack)
import Environment as Env
import Expressions (Expr, tryParse)
import FitchRules as Fitch
import Halogen (ClassName(..))
import Halogen as H
import Halogen.HTML (HTML)
import Halogen.HTML as HH
import Halogen.HTML.Events as HE
import Halogen.HTML.Properties as HP
import Rules (Rule, RuleInstance)
import Rules as Rules
import Scope (Scope)
import Scope as Scope

data HistoryItem
  = UsedRule { ruleInstance :: RuleInstance, newFacts :: Set Expr }
  | AddedPremisse { premisse :: Expr }

useRule :: RuleInstance -> State -> State
useRule ruleInst state =
  let (Tuple newKnowledge newStack) = Env.runWith state.currentStack (Env.tryApply ruleInst)
  in case newKnowledge of
    Nothing -> state
    Just facts -> 
      state { currentStack = newStack
            , history = UsedRule { ruleInstance: ruleInst, newFacts: facts } : state.history
            }

addPremisse :: Expr -> State -> State
addPremisse prem state =
  let (Tuple _ newStack) = Env.runWith state.currentStack (Env.addExpr prem)
  in state 
    { currentStack = newStack
    , history = AddedPremisse { premisse: prem } : state.history
    }

data Action
  = ShowRuleModal Rule
  | HandleButton Button.Message
  | HandleRuleModal RuleDlg.Message
  | CheckButtonState

type State =
  { toggleCount :: Int
  , buttonState :: Maybe Boolean
  , showRuleModal :: Maybe Rule
  , premisses :: Array Expr
  , currentStack :: AssumptionStack
  , history :: List HistoryItem
  }

type ChildSlots =
  ( button :: Button.Slot Unit
  , newRuleModal :: RuleDlg.Slot Unit
  )

_button :: SProxy "button"
_button = SProxy

_newRuleModal :: SProxy "newRuleModal"
_newRuleModal = SProxy

component :: forall q i o m. MonadEffect m => H.Component HH.HTML q i o m
component =
  H.mkComponent
    { initialState
    , render
    , eval: H.mkEval $ H.defaultEval { handleAction = handleAction }
    }

initialState :: forall i. i -> State
initialState _ =
  either (const identity) addPremisse (tryParse "a | b") $
  either (const identity) addPremisse (tryParse "~(~a)") $
  { toggleCount: 0
  , buttonState: Nothing
  , showRuleModal: Nothing
  , premisses: []
  , currentStack:  Env.NoAssumptions Scope.empty
  , history: List.Nil
  }

render :: forall m. MonadEffect m => State -> H.ComponentHTML Action ChildSlots m
render state = HH.div_
  [ case state.showRuleModal of
      Just rule -> HH.slot _newRuleModal unit 
        RuleDlg.component 
          { scope: Env.scopeOf state.currentStack 
          , rule
          } 
        (Just <<< HandleRuleModal)
      Nothing -> HH.text "" 
  , HH.div_
    [ HH.slot _button unit Button.component unit (Just <<< HandleButton)
    , HH.p_
        [ HH.text ("Button has been toggled " <> show state.toggleCount <> " time(s)") ]
    , HH.p_
        [ HH.text
            $ "Last time I checked, the button was: "
            <> (maybe "(not checked yet)" (if _ then "on" else "off") state.buttonState)
            <> ". "
        , HH.button
            [ HE.onClick (\_ -> Just CheckButtonState) ]
            [ HH.text "Check now" ]
        ]
    , showRuleButtons (Env.scopeOf state.currentStack) Fitch.rules
    ]
  ]

handleAction ::forall o m. Action -> H.HalogenM State Action ChildSlots o m Unit
handleAction = case _ of
  ShowRuleModal rule ->
    H.modify_ (\st -> st { showRuleModal = Just rule })
  HandleRuleModal RuleDlg.Canceled ->
    H.modify_ (\st -> st { showRuleModal = Nothing })
  HandleRuleModal (RuleDlg.NewRule _) ->
    H.modify_ (\st -> st { showRuleModal = Nothing })
  HandleButton (Button.Toggled _) -> do
    H.modify_ (\st -> st { toggleCount = st.toggleCount + 1 })
  CheckButtonState -> do
    buttonState <- H.query _button unit $ H.request Button.IsOn
    H.modify_ (_ { buttonState = buttonState })

exampleRule :: Rule
exampleRule = Fitch.notElimination


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