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
##  Check si le disque existe                                                    
##############################################################################
if [ ! -b "/dev/$DISK" ]; then
  log_prompt "ERROR" && echo "Le disque /dev/$DISK n'existe pas."
  exit 1
fi

##############################################################################
## Formatage du disque                                                     
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
## Création des tables de partition                                                       
##############################################################################
log_prompt "INFO" && echo "Création de table de partition ${MODE} pour /dev/${DISK}" && echo ""

if [ "$MODE" = "UEFI" ]; then
  parted --script -a optimal /dev/"${DISK}" mklabel gpt || { log_prompt "ERROR" && echo "Échec de la création de la table de partition GPT."; exit 1; }
else
  parted --script -a optimal /dev/"${DISK}" mklabel msdos || { log_prompt "ERROR" && echo "Échec de la création de la table de partition MBR."; exit 1; }
fi

log_prompt "SUCCESS" && echo "Table de partition créée avec succès." && echo ""

##############################################################################
## Création des partition + Formatage                                                     
##############################################################################
clear && parted /dev/"${DISK}" print

# Récupére le nombres de partition à créer
log_prompt "INFO" && read -p "Combien de partitions souhaitez-vous créer ? " num_partitions && echo ""

# Vérifier si le nombre est valide (un entier positif)
if ! [[ "$num_partitions" =~ ^[0-9]+$ ]] || [ "$num_partitions" -le 0 ]; then
  log_prompt "ERROR" && echo "Veuillez entrer un nombre entier positif." && exit 1
fi

start_point="1MiB" # Initialisation du point de départ

# Validation de la taille de la partition avec recommandation pour EFI/Boot
for ((i = 1; i <= num_partitions; i++)); do

  clear && parted /dev/"${DISK}" print

  while true; do

    log_prompt "INFO" && echo "Choisissez le type de partition pour /dev/${DISK}${i} :" && echo ""

    # Options communes
    log_prompt "INFO" && echo "1) EXT4"
    log_prompt "INFO" && echo "2) BTRFS"
    log_prompt "INFO" && echo "3) XFS"

    if [[ "$MODE" == "UEFI" ]]; then
      log_prompt "INFO" && echo "4) ESP [UEFI BOOT]" # Option efi seulement en mode UEFI
    fi
    if [[ "$SWAP_FILE" == "Off" ]]; then
      log_prompt "INFO" && echo "$(( $MODE == "UEFI" ? 5 : 4 ))) LINUX-SWAP" # Option swap seulement si SWAP_FILE = "Off"
    fi

    echo ""

    # Demande du choix utilisateur
    log_prompt "INFO" && read -p "Votre choix : " format_choice && echo ""

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
          partition_type="ESP"
          break
        elif [[ "$SWAP_FILE" == "Off" ]]; then
          partition_type="linux-swap"
          break
        else
          log_prompt "WARNING" && echo "L'option linux-swap n'est pas disponible car un fichier swap est activé." && echo ""
        fi
        ;;
      5)
        if [[ "$SWAP_FILE" == "Off" && "$MODE" == "UEFI" ]]; then
          partition_type="linux-swap"
          break
        else
          log_prompt "ERROR" && echo "Choix invalide. Veuillez entrer un numéro valide." && echo ""
        fi
        ;;
      *)
        log_prompt "ERROR" && echo "Choix invalide. Veuillez entrer un numéro valide." && echo ""
        ;;
    esac
    echo "Veuillez faire un choix valide." && echo ""
  done

  log_prompt "INFO" && echo "Type de partition sélectionné : $partition_type" && echo ""

  # Validation de la taille de la partition
  while true; do
    if [[ "$partition_type" == "ESP" ]]; then
      log_prompt "INFO" && read -p "Veuillez entrer une taille de partition pour /dev/${DISK}${i} [par défaut : 512MiB] : " partition_size && echo ""
      partition_size=${partition_size:-512MiB}  # Taille par défaut
    else
      log_prompt "INFO" && read -p "Veuillez entrer une taille de partition (ex: 10GiB ou 100%) pour /dev/${DISK}${i} : " partition_size && echo ""
    fi

    # Supprimer les espaces avant et après la saisie de l'utilisateur
    partition_size=$(echo "$partition_size" | xargs)

    # Vérifier la validité de la taille entrée
    if [[ "$partition_size" =~ ^[0-9]+(MiB|GiB)$ || "$partition_size" == "100%" ]]; then
      break
    else
      log_prompt "ERROR" && echo "Taille de partition invalide. Veuillez entrer une taille valide (ex: 10GiB, 512MiB ou 100%)." && echo ""
    fi
  done

  # Création de la partition
  log_prompt "INFO" && echo "Création de la partition /dev/${DISK}${i} de type $partition_type avec une taille de $partition_size" && echo ""

  partition_size_unit=$(echo "$partition_size" | sed 's/[0-9]//g' | xargs)
  partition_size_value=$(echo "$partition_size" | sed 's/[^\0-9]//g')

  if [[ "$partition_size_unit" == "MiB" ]]; then
    end_point=$partition_size_value # Valeur deja en MiB


  elif [[ "$partition_size_unit" == "GiB" ]]; then
    end_point=$((partition_size_value * 1024))  # Conversion GiB en MiB
    

  elif [[ "$partition_size_unit" == "%" ]]; then
    parted --script -a optimal /dev/"${DISK}" mkpart primary $partition_type ${start_point}MiB 100%
    mkfs."${partition_type}" "/dev/${DISK}${i}"
    break  # Arrêter la boucle car tout l'espace est utilisé

  else
    echo "Erreur : unité invalide. Veuillez entrer 'MiB' ou 'GiB'."
    exit 1
  fi

  # Si c'est la première partition EFI, définir l'option esp
  if [[ "$partition_type" == "ESP" ]]; then
    parted --script -a optimal /dev/"${DISK}" mkpart "$partition_type" fat32 1MiB ${end_point}MiB || { log_prompt "ERROR" && echo "Échec de la création de la partition EFI."; exit 1; }
    parted --script -a optimal /dev/"${DISK}" set "$i" esp on || { log_prompt "ERROR" && echo "Échec de la configuration de la partition EFI."; exit 1; }

    start_point=$end_point
    
    mkfs.fat -F32 "/dev/${DISK}${i}"

  else

    parted --script -a optimal /dev/"${DISK}" mkpart primary "$partition_type" ${start_point}MiB ${end_point}MiB || { log_prompt "ERROR" && echo "Échec de la création de la partition."; exit 1; }

    # Mettre à jour le point de départ pour la prochaine partition
    start_point=$((start_point + end_point))
  
    if [[ "$partition_type" == "linux-swap" ]]; then
      mkswap "/dev/${DISK}${i}"
      swapon "/dev/${DISK}${i}"
    else
      mkfs."${partition_type}" "/dev/${DISK}${i}"
    fi

  fi

  # Mettre à jour le point de départ pour la prochaine partition
  # start_point=$(parted /dev/"${DISK}" print free | grep 'Free Space' | tail -1 | awk '{print $1}')

  log_prompt "SUCCESS" && echo "Partition /dev/${DISK}${i} créée avec succès." && echo ""

done

##############################################################################
## Montage des partition                                                
##############################################################################
#!/bin/bash

clear
parted /dev/"${DISK}" print && echo ""

log_prompt "WARNING" && echo "La partition sera monté sur /mnt/gentoo : "
log_prompt "INFO" && read -p "Choisissez sur quelle partition sera installé le système (ex: 3 pour /dev/sda3) : " root_partition_num && echo ""

# Vérifier que la partition spécifiée existe
if [ ! -b "/dev/${DISK}${root_partition_num}" ]; then
  log_prompt "ERROR" && echo "La partition /dev/${DISK}${root_partition_num} n'existe pas."
  exit 1
fi

# Monter la partition root
mkdir -p "$MOUNT_POINT"
if mount "/dev/${DISK}${root_partition_num}" "$MOUNT_POINT"; then
  log_prompt "SUCCESS" && echo "Partition root montée avec succès."
else
  log_prompt "ERROR" && echo "Échec du montage de la partition root."
  exit 1
fi

echo ""

# Demander à l'utilisateur s'il souhaite monter des partitions supplémentaires
log_prompt "INFO" && read -p "Souhaitez-vous monter d'autres partitions ? (y/n) : " mount_more && echo ""

if [ "$mount_more" = "y" ]; then
  # Obtenir toutes les partitions sauf celle de root
  partitions=($(lsblk -lnp -o NAME | grep "^/dev/${DISK}" | grep -v "/dev/${DISK}${root_partition_num}"))

  for partition in "${partitions[@]}"; do

    partition_num=${partition##*/}

    # Vérifier si la partition est une partition swap
    if blkid "$partition" | grep -q "TYPE=\"swap\""; then
      log_prompt "WARNING" && echo "La partition $partition est une partition swap, elle sera activée automatiquement." && echo ""
      continue  # Passer à la partition suivante sans demander de point de montage
    fi

    while true; do
      log_prompt "INFO" && read -p "Nommer le point de montage de la partition ${partition##*/} (ex. efi - [sans le /]) : " partition_name && echo ""

      if [ -n "$partition_name" ] && [[ "$partition_name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        mkdir -p "$MOUNT_POINT/$partition_name"
        if mount "$partition" "$MOUNT_POINT/$partition_name"; then
          log_prompt "SUCCESS" && echo "Partition $partition montée sur $MOUNT_POINT/$partition_name."
        else
          log_prompt "ERROR" && echo "Échec du montage de $partition."
        fi
        echo ""
        break
      else
        log_prompt "ERROR" && echo "Le nom du point de montage est invalide. Essayez à nouveau." && echo ""
      fi
    done
    
  done
fi


##############################################################################
## Creation of the swap file                                                
##############################################################################
if [ "$SWAP_FILE" = "On" ]; then
    log_prompt "INFO" && echo "création du fichier swap" && echo ""
    mkdir --parents $MOUNT_POINT/swap
    fallocate -l "${SWAP_FILE_SIZE}MiB" $MOUNT_POINT/swap/swapfile
    # dd if=/dev/zero of=$MOUNT_POINT/swap bs=1M count=${SWAP_FILE_SIZE}  
    chmod 600 $MOUNT_POINT/swap/swapfile                            
    mkswap $MOUNT_POINT/swap/swapfile                                
    swapon $MOUNT_POINT/swap/swapfile  
    log_prompt "SUCCESS" && echo "Terminée" && echo ""
fi