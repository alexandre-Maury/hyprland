#!/bin/bash

# script disk.sh

# Mettre un mode verbose pour la création de partition et le formatage pour que l'utilisateur sache ou il en ait ...
# Fusionner partitionning + formating

set -e  # Quitte immédiatement en cas d'erreur.

source functions.sh  # Charge les fonctions définies dans le fichier fonction.sh.
source config.sh # Inclure le fichier de configuration.
chmod +x *.sh # Rendre les scripts exécutables.

##############################################################################
## Arguments                                                    
##############################################################################
DISK="${1}"
chmod +x *.sh # Rendre les scripts exécutables.

log_prompt "INFO" && echo "Mode de démarrage détecté : $MODE" && echo ""

##############################################################################
##  Check if the disk exists                                                    
##############################################################################
if [ ! -b "/dev/$DISK" ]; then
  log_prompt "ERROR" && echo "Le disque /dev/$DISK n'existe pas."
  exit 1
fi

##############################################################################
## Formatting disk                                                       
##############################################################################
if prompt_confirm "Souhaitez-vous nettoyer le disque ? (Y/n)"; then
  

  MOUNTED_PARTITIONS=$(lsblk --list --noheadings /dev/"${DISK}" | tail -n +2 | awk '{print $1}')
  echo ""
  log_prompt "INFO" && read -p "Combien de passe souhaitez-vous faire ? " SHRED_PASS 
  echo ""

  if ! [[ "$SHRED_PASS" =~ ^[0-9]+$ ]]; then
      log_prompt "ERROR" && echo "veuillez entrer un nombre valide de passes."
      exit 1
  fi

  # Désactiver toutes les partitions swap
  log_prompt "INFO" && echo "Désactivation des partitions swap..." && echo ""
  
  # Désactive tous les swaps
  swapoff -a
  # Vérifie si le swap est désactivé
  if ! grep -q "swap" /proc/swaps; then
      log_prompt "SUCCESS" && echo "Terminée" && echo ""
  fi

  log_prompt "INFO" && echo "Lancement de shred sur /dev/"${DISK}" avec ${SHRED_PASS} passes..."
  echo ""

  wipefs --all /dev/"${DISK}"

  shred -n "${SHRED_PASS}" -v "/dev/${DISK}"

  # Si des partitions sont montées, les démonter
  if [[ -n "${MOUNTED_PARTITIONS}" ]]; then
      log_prompt "INFO" && echo "Démontage des partitions montées sur /dev/${DISK}..."
      echo ""
      for partition in ${MOUNTED_PARTITIONS}; do
        if umount "/dev/${partition}"; then
          log_prompt "SUCCESS" && echo "Terminée"
          echo ""
        else
          log_prompt "ERROR" && echo "La partition /dev/${partition} n'a pas pu etre démonté."
          echo ""
        fi
      done
  else
      log_prompt "SUCCESS" && echo "Terminée"
      echo ""
  fi
fi

echo ""

##############################################################################
## Initialize the partition table with parted                                                         
##############################################################################
log_prompt "INFO" && echo "Création de table de partition ${MODE} pour /dev/${DISK}" && echo ""

if [ "$MODE" = "UEFI" ]; then
  parted --script -a optimal /dev/"${DISK}" mklabel gpt || { log_prompt "ERROR" && echo "Échec de la création de la table de partition GPT."; exit 1; }
else
  parted --script -a optimal /dev/"${DISK}" mklabel msdos || { log_prompt "ERROR" && echo "Échec de la création de la table de partition MBR."; exit 1; }
fi

log_prompt "SUCCESS" && echo "Table de partition créée avec succès." && echo ""

##############################################################################
## Ask the user how many additional partitions to create                                                      
##############################################################################
clear && parted /dev/"${DISK}" print

# Récupére le nombres de partition à créer
log_prompt "INFO" && read -p "Combien de partitions souhaitez-vous créer ? " num_partitions && echo ""

# Vérifier si le nombre est valide (un entier positif)
if ! [[ "$num_partitions" =~ ^[0-9]+$ ]] || [ "$num_partitions" -le 0 ]; then
  log_prompt "ERROR" && echo "Veuillez entrer un nombre entier positif." && exit 1
fi

# Initialisation du point de départ
start_point=0%

# Validation de la taille de la partition avec recommandation pour EFI/Boot
for ((i = 1; i <= num_partitions; i++)); do

  clear && parted /dev/"${DISK}" print

  while true; do

    log_prompt "INFO" && echo "Choisissez le type de partition pour /dev/${DISK}${i} :"

    # Options communes
    log_prompt "INFO" && echo "1) ext4"
    log_prompt "INFO" && echo "2) btrfs"
    log_prompt "INFO" && echo "3) xfs"

    # Option spécifique à UEFI
    if [[ "$MODE" == "UEFI" ]]; then
      log_prompt "INFO" && echo "4) efi" # Option efi seulement en mode UEFI
    fi

    # Option partition swap si SWAP_FILE est désactivé
    if [[ "$SWAP_FILE" == "Off" ]]; then
      log_prompt "INFO" && echo "$(( $MODE == "UEFI" ? 5 : 4 ))) linux-swap" # Option swap seulement si SWAP_FILE = "Off"
    fi

    # Demande du choix utilisateur
    log_prompt "INFO" && read -p "Votre choix : " format_choice

    # Validation du choix
    case $format_choice in
      1)
        partition_type="ext4"
        break
        ;;
      2)
        partition_type="btrfs"
        break
        ;;
      3)
        partition_type="xfs"
        break
        ;;
      4)
        if [[ "$MODE" == "UEFI" ]]; then
          partition_type="efi"
          break
        elif [[ "$SWAP_FILE" == "Off" ]]; then
          partition_type="linux-swap"
          break
        else
          log_prompt "WARNING" && echo "L'option linux-swap n'est pas disponible car un fichier swap est activé."
        fi
        ;;
      5)
        if [[ "$SWAP_FILE" == "Off" && "$MODE" == "UEFI" ]]; then
          partition_type="linux-swap"
          break
        else
          log_prompt "ERROR" && echo "Choix invalide. Veuillez entrer un numéro valide."
        fi
        ;;
      *)
        log_prompt "ERROR" && echo "Choix invalide. Veuillez entrer un numéro valide."
        ;;
    esac
    echo "Veuillez faire un choix valide."
  done

  echo "Type de partition sélectionné : $partition_type"

  # Validation de la taille de la partition
  while true; do
    if [[ "$partition_type" == "efi" ]]; then
      log_prompt "INFO" && read -p "Veuillez entrer une taille de partition pour /dev/${DISK}${i} [par défaut : 512 MiB] : " partition_size && echo ""
      partition_size=${partition_size:-512MiB}  # Taille par défaut
    else
      log_prompt "INFO" && read -p "Veuillez entrer une taille de partition (ex: 10GiB ou 100%) pour /dev/${DISK}${i} : " partition_size && echo ""
    fi

    # Supprimer les espaces avant et après la saisie de l'utilisateur
    partition_size=$(echo "$partition_size" | xargs)

    echo "Vous avez entrer : $partition_size"

    # Vérifier la validité de la taille entrée
    if [[ "$partition_size" =~ ^[0-9]+(MiB|GiB)$ || "$partition_size" == "100%" ]]; then
      break
    else
      log_prompt "ERROR" && echo "Taille de partition invalide. Veuillez entrer une taille valide (ex: 10GiB, 512MiB ou 100%)."
    fi
  done

  # Création de la partition
  log_prompt "INFO" && echo "Création de la partition /dev/${DISK}${i} de type $partition_type avec une taille de $partition_size"

  # Si c'est la première partition EFI, définir l'option esp
  if [[ "$partition_type" == "efi" ]]; then
    parted --script -a optimal /dev/"${DISK}" mkpart primary "$partition_type" "$start_point" "$partition_size" || { log_prompt "ERROR" && echo "Échec de la création de la partition EFI."; exit 1; }
    parted --script -a optimal /dev/"${DISK}" set "$i" esp on || { log_prompt "ERROR" && echo "Échec de la configuration de la partition EFI."; exit 1; }
  
  else
    parted --script -a optimal /dev/"${DISK}" mkpart primary "$partition_type" "$start_point" "$partition_size" || { log_prompt "ERROR" && echo "Échec de la création de la partition."; exit 1; }
  fi

  # Mettre à jour le point de départ pour la prochaine partition
  start_point=$(parted /dev/"${DISK}" print | tail -1 | awk '{print $3}')  # Récupérer la fin de la dernière partition

  log_prompt "SUCCESS" && echo "Partition /dev/${DISK}${i} créée avec succès."

  echo "le point de depart : $start_point"

done

