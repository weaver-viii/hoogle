{-|
    Deal with variable bindings/alpha renaming in searches
    And with restrictions
-}

module Hoogle.DataBase.TypeSearch.Binding(
    Binding, newBinding, newBindingUnbox, newBindingRebox,
    addBinding, costBinding, mergeBindings, bindings
    ) where

import Hoogle.TypeSig.All
import General.Code
import Hoogle.DataBase.TypeSearch.Score
import qualified Data.Map as Map
import qualified Data.Set as Set


type Var = String
type Lit = String


type Bind = Map.Map Var (Maybe Lit, Set.Set Var)

data Binding = Binding !Int [Box] Bind Bind
               deriving Show

data Box = Unbox | Rebox
           deriving (Eq,Show)


instance Eq Binding where
    (==) = (==) `on` costBinding

instance Ord Binding where
    compare = compare `on` costBinding


costBinding :: Binding -> Int
costBinding (Binding x _ _ _) = x


newBinding, newBindingUnbox, newBindingRebox :: Binding
newBinding      = Binding 0          []      Map.empty Map.empty
newBindingUnbox = Binding scoreUnbox [Unbox] Map.empty Map.empty
newBindingRebox = Binding scoreRebox [Rebox] Map.empty Map.empty



cost b v = if b then v else 0


addBinding :: (Type, Type) -> Binding -> Maybe Binding
addBinding (TVar a, TVar b) (Binding c box x y) = Just $ Binding c2 box x2 y2
    where (x2,cx) = addVar a b x
          (y2,cy) = addVar b a y
          c2 = c + cost cx scoreDupVarQuery + cost cy scoreDupVarResult

addBinding (TVar a, TLit b) (Binding c box x y) = do
    (x2,cx) <- addLit a b x
    return $ Binding (c + cost cx scoreRestrict) box x2 y
addBinding (TLit a, TVar b) (Binding c box x y) = do
    (y2,cy) <- addLit b a y
    return $ Binding (c + cost cy scoreUnrestrict) box x y2

addBinding (TLit a, TLit b) bind = if a == b then Just bind else Nothing


addVar :: Var -> Var -> Bind -> (Bind, Bool)
addVar a b mp = case Map.lookup a mp of
    Nothing -> (Map.insert a (Nothing, Set.singleton b) mp, False)
    Just (l, vs) | b `Set.member` vs -> (mp, False)
                 | otherwise -> (Map.insert a (l, Set.insert b vs) mp, True)


addLit :: Var -> Lit -> Bind -> Maybe (Bind, Bool)
addLit a b mp | l == Just b = Just (mp, False)
              | isJust l = Nothing
              | otherwise = Just (Map.insert a (Just b, vs) mp, True)
    where (l, vs) = Map.findWithDefault (Nothing, Set.empty) a mp



mergeBindings :: [Binding] -> Maybe Binding
mergeBindings bs = do
    let (box,ls,rs) = unzip3 [(b,l,r) | Binding _ b l r <- bs]
        (bl,br) = (Map.unionsWith f ls, Map.unionsWith f rs)
        cb = sum [if b == Unbox then scoreUnbox else scoreRebox | b <- concat box]
    cl <- score scoreDupVarQuery  scoreRestrict   bl
    cr <- score scoreDupVarResult scoreUnrestrict br
    return $ Binding (cl+cr+cb) (concat box) bl br
    where
        f (l1,vs1) (l2,vs2)
            | l1 /= l2 && isJust l1 && isJust l2 = (Just "", vs1)
            | otherwise = (l1 `mplus` l2, Set.union vs1 vs2)

        score var restrict = liftM sum . mapM g . Map.elems
            where
                g (Just "", _) = Nothing
                g (l, vs) = Just $ cost (isJust l) restrict + var * (Set.size vs - 1)


bindings :: Binding -> [(Type, Type)]
bindings (Binding _ _ a b) =
    [(TVar v, t) | (v,(l,vs)) <- Map.toList a, t <- [TLit l | Just l <- [l]] ++ map TVar (Set.toList vs)] ++
    [(TVar v, TLit l) | (v,(Just l,_)) <- Map.toList b]
